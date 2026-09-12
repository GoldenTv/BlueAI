import { streamText, wrapLanguageModel, extractReasoningMiddleware } from 'ai';
import { createOpenAI } from '@ai-sdk/openai';
import { normalizeGatewayStream } from './gateway-stream';
import { ApiError, CloudEnv, CloudStore } from './cloud-store';

export interface Env extends CloudEnv { AI_BASE_URL?: string; AI_MODEL?: string; ALLOWED_ORIGINS?: string; }
interface Context { waitUntil(promise: Promise<unknown>): void; }
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SYSTEM_PROMPT =
  'You are BlueAI, a helpful, intelligent, and friendly AI assistant. ' +
  'When thinking through problems, coding tasks, or questions, you may include your thought process and reasoning inside <think>...</think> tags before providing the final answer. ' +
  'Always provide clear and well-structured answers in Thai or English as requested. Use Markdown formatting and LaTeX for all mathematical ' +
  'formulas: use $...$ or \\(...\\) for inline math, and $$...$$ or \\[...\\] for block math.';

function cors(request: Request, env: Env): Record<string, string> {
  const origin = request.headers.get('Origin');
  const allowed = (env.ALLOWED_ORIGINS ?? '').split(',').map(s => s.trim());
  return {
    ...(origin && allowed.includes(origin) ? { 'Access-Control-Allow-Origin': origin } : {}),
    Vary: 'Origin', 'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type, X-AI-API-Key', 'Access-Control-Max-Age': '86400',
  };
}
function json(data: unknown, status: number, headers: Record<string,string>) {
  return new Response(JSON.stringify(data), {status, headers: {...headers, 'Content-Type':'application/json', 'Cache-Control':'no-store'}});
}
async function readBody(request: Request): Promise<any> {
  if (Number(request.headers.get('Content-Length') ?? 0) > 2_000_000) throw new ApiError('INVALID_INPUT','ข้อมูลมีขนาดใหญ่เกินไป',413);
  const text = await request.text();
  if (text.length > 2_000_000) throw new ApiError('INVALID_INPUT','ข้อมูลมีขนาดใหญ่เกินไป',413);
  try { const value = JSON.parse(text || '{}'); if (!value || Array.isArray(value) || typeof value !== 'object') throw 0; return value; }
  catch { throw new ApiError('INVALID_INPUT','ข้อมูล JSON ไม่ถูกต้อง',400); }
}

export default {
  async fetch(request: Request, env: Env, ctx?: Context): Promise<Response> {
    const headers = cors(request, env);
    if (request.method === 'OPTIONS') return new Response(null, {status:204, headers});
    const path = new URL(request.url).pathname;
    if (request.method !== 'POST') return json({code:'METHOD_NOT_ALLOWED',error:'โปรดใช้ POST'},405,headers);
    const stop = path.match(/^\/v1\/chat\/([0-9a-f-]+)\/stop$/i);
    if (path !== '/v1/chat' && !stop) return json({code:'NOT_FOUND',error:'ไม่พบ API นี้'},404,headers);
    try {
      const match = request.headers.get('Authorization')?.match(/^Bearer (\S+)$/i);
      if (!match) throw new ApiError('AUTH_REQUIRED','กรุณาเข้าสู่ระบบ',401);
      const store = new CloudStore(env, match[1]);
      await store.authenticate();
      if (stop) {
        if (!UUID.test(stop[1])) throw new ApiError('INVALID_INPUT','รหัสคำขอไม่ถูกต้อง',400);
        const body = await readBody(request);
        if (typeof body.content === 'string') await store.rpc('save_chat', {
          p_request_id: stop[1], p_content: body.content,
          p_reasoning: typeof body.reasoning === 'string' ? body.reasoning : '', p_status:'stopped',
        });
        const status = await store.rpc('stop_chat', {p_request_id:stop[1]});
        return json({status},200,headers);
      }
      const body = await readBody(request);
      for (const field of ['conversationId','requestId','messageId']) {
        if (typeof body[field] !== 'string' || !UUID.test(body[field])) throw new ApiError('INVALID_INPUT','รหัสห้องหรือข้อความไม่ถูกต้อง',400);
      }
      if (typeof body.prompt !== 'string' || !body.prompt.trim() || body.prompt.length > 32000 || typeof body.model !== 'string' || !body.model.trim() || body.model.length > 200) {
        throw new ApiError('INVALID_INPUT','ข้อความหรือโมเดลไม่ถูกต้อง',400);
      }
      const apiKey = request.headers.get('X-AI-API-Key')?.trim();
      if (!apiKey) throw new ApiError('AI_KEY_REQUIRED','โปรดใส่ API Key ในหน้าตั้งค่า',400);
      if (request.signal.aborted) throw new ApiError('INTERRUPTED','ยกเลิกคำขอแล้ว',409);
      const reservation = await store.rpc('begin_chat', {
        p_conversation_id:body.conversationId, p_request_id:body.requestId,
        p_message_id:body.messageId, p_prompt:body.prompt.trim(), p_model:body.model.trim(),
      });
      if (!reservation.started) return json({code:'REQUEST_EXISTS',run:reservation.run},409,headers);
      return startStream(request, env, store, body, apiKey, headers, ctx);
    } catch (error) {
      const e = error instanceof ApiError ? error : new ApiError('INTERNAL_ERROR','เกิดข้อผิดพลาดภายในระบบ');
      return json({code:e.code,error:e.message},e.status,headers);
    }
  },
};

function startStream(request: Request, env: Env, store: CloudStore, body: any, apiKey: string, headers: Record<string,string>, ctx?: Context) {
  const abort = new AbortController();
  const encoder = new TextEncoder();
  let content = '', reasoning = '', dirty = false, closed = false, terminal = false;
  let thinkingSeconds: number | null = null;
  let lastSaved = Date.now();
  const started = Date.now();
  let timer: ReturnType<typeof setInterval> | undefined;
  let idle: ReturnType<typeof setTimeout> | undefined;
  let writes: Promise<unknown> = Promise.resolve();
  const keepAlive = (p: Promise<unknown>) => { ctx?.waitUntil(p); p.catch(() => {}); };
  function save(status: string, code?: string, error?: string) {
    const snapshot = {p_request_id:body.requestId,p_content:content,p_reasoning:reasoning,p_status:status,
      p_error_code:code ?? null,p_error_message:error ?? null,p_thinking_seconds:thinkingSeconds};
    dirty = false;
    const task = writes.catch(() => {}).then(async () => {
      const result = await store.rpc('save_chat', snapshot);
      lastSaved = Date.now();
      if (result !== 'streaming') terminal = true;
      return result as string;
    });
    writes = task;
    return task;
  }
  function cleanup() { clearInterval(timer); clearTimeout(idle); request.signal.removeEventListener('abort', onAbort); }
  function onAbort() {
    abort.abort(); cleanup();
    if (!terminal) keepAlive(save('interrupted', 'INTERRUPTED','การเชื่อมต่อถูกขัดจังหวะ'));
  }
  request.signal.addEventListener('abort', onAbort, {once:true});
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      let checkpointPending = false;
      const emit = (value: unknown) => { if (!closed) controller.enqueue(encoder.encode(`data: ${JSON.stringify(value)}\n\n`)); };
      const pump = async () => {
        try {
          if (request.signal.aborted) { onAbort(); throw new ApiError('INTERRUPTED','ยกเลิกคำขอแล้ว',409); }
          const messages = await store.history(body.conversationId);
          const provider = createOpenAI({
            baseURL:(env.AI_BASE_URL || 'https://ai.psu.blue/v1').replace(/\/$/,''), apiKey, compatibility:'compatible',
            fetch: async (input, init) => {
              const response = await fetch(input, init);
              return response.body && response.headers.get('content-type')?.includes('text/event-stream')
                ? new Response(normalizeGatewayStream(response.body), {status:response.status,headers:response.headers}) : response;
            },
          });
          const resetIdle = () => { clearTimeout(idle); idle = setTimeout(() => abort.abort(new Error('TIMEOUT')),90000); };
          resetIdle();
          timer = setInterval(() => {
            if (terminal || (!dirty && Date.now()-lastSaved < 20000) || checkpointPending) return;
            checkpointPending = true;
            keepAlive(save('streaming').then(status => { if(status !== 'streaming') abort.abort(); })
              .catch(() => abort.abort(new Error('SAVE_FAILED'))).finally(() => { checkpointPending=false; }));
          },2000);
          const result = streamText({model:wrapLanguageModel({model:provider(body.model),middleware:extractReasoningMiddleware({tagName:'think'})}),
            system:SYSTEM_PROMPT,messages,temperature:0.7,abortSignal:abort.signal,maxRetries:0});
          let finished = false;
          for await (const part of result.fullStream) {
            resetIdle();
            if (abort.signal.aborted) throw new Error('ABORTED');
            if (part.type === 'error') throw new ApiError('GATEWAY_ERROR','โมเดลตอบกลับไม่สำเร็จ',502);
            if (part.type === 'finish') { finished = part.finishReason === 'stop'; }
            if (part.type === 'text-delta' || part.type === 'reasoning') {
              if (part.type === 'text-delta') {
                if (thinkingSeconds === null && part.textDelta) thinkingSeconds = Math.max(1,Math.floor((Date.now()-started)/1000));
                content += part.textDelta;
              } else reasoning += part.textDelta;
              dirty = true;
              emit({type:part.type === 'text-delta' ? 'text':'thinking',delta:part.textDelta});
            }
          }
          if (!finished || !content.trim()) throw new ApiError('INCOMPLETE_RESPONSE', 'โมเดลยังไม่ส่งคำตอบหลักที่สมบูรณ์',502);
          cleanup();
          const status = await save('completed');
          if (status !== 'completed') throw new ApiError('INTERRUPTED','คำตอบถูกหยุดก่อนเสร็จ',409);
          if (!closed) { controller.enqueue(encoder.encode('data: [DONE]\n\n')); controller.close(); closed=true; }
        } catch (error) {
          cleanup(); abort.abort();
          const e = error instanceof ApiError ? error : new ApiError('INTERRUPTED','การตอบกลับถูกขัดจังหวะ');
          let code = e.code, message = e.message;
          try { if (!terminal) await save(closed || request.signal.aborted ? 'interrupted':'error', code, message); }
          catch { code='SAVE_FAILED'; message='ยังยืนยันการบันทึกไม่ได้ กรุณาเชื่อมต่อแล้วตรวจบทสนทนาอีกครั้ง'; }
          if (!closed) { emit({type:'error',code,error:message}); controller.close(); closed=true; }
        }
      };
      keepAlive(pump());
    },
    cancel() { closed=true; onAbort(); return writes.then(() => {}, () => {}); },
  });
  return new Response(stream, {headers:{...headers,'Content-Type':'text/event-stream; charset=utf-8','Cache-Control':'no-cache, no-store, no-transform','X-Accel-Buffering':'no'}});
}
