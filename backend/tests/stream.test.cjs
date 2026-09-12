const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const ts = require('typescript');

// Run the actual Worker and installed AI SDK without deployment or API calls.
require.extensions['.ts'] = (module, filename) => {
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  });
  module._compile(compiled.outputText, filename);
};
const actualWorker = require('../src/index.ts').default;
let state;
beforeEach(() => { state={started:true,saves:[],calls:[],upstream:0}; });
const worker = { async fetch(req) {
  const gateway=global.fetch;
  global.fetch=async (url,init) => {
    const path=String(url);
    if(!path.startsWith('https://db.test')) { state.upstream++; state.aiHeaders=init.headers; state.aiBody=JSON.parse(init.body); return gateway(url,init); }
    state.calls.push({path,headers:init.headers});
    const json=(data,status=200)=>Response.json(data,{status});
    if(path.includes('/auth/v1/user')) return state.authError?json({message:'expired'},401):json({id:'user-a'});
    const payload=init.body?JSON.parse(init.body):{};
    if(path.endsWith('/begin_chat')) return state.beginError?json({message:state.beginError},400):json({started:state.started,run:{status:'streaming'}});
    if(path.includes('/messages?')) return json([{role:'user',content:'database prompt'}]);
    if(path.endsWith('/save_chat')) {
      state.saves.push(payload);
      return state.saveError?json({message:'database down'},503):json(payload.p_status);
    }
    if(path.endsWith('/stop_chat')) return json('stopped');
    throw new Error('Unexpected database endpoint: '+path);
  };
  return actualWorker.fetch(req,{SUPABASE_URL:'https://db.test',SUPABASE_PUBLISHABLE_KEY:'publishable'});
}};
const { normalizeGatewayStream } = require('../src/gateway-stream.ts');
const originalFetch = global.fetch;
afterEach(() => { global.fetch = originalFetch; });

// Hold the upstream open: final-output assertions alone cannot detect buffering.
for (const [name, first, second, answer] of [
  ['reasoning_content', {reasoning_content:'first'}, {reasoning_content:' second'}, {content:'answer'}],
  ['thinking', {thinking:'first'}, {thinking:' second'}, {content:'answer'}],
  ['content blocks', {content:[{type:'thinking',thinking:'first'}]}, {content:[{type:'thinking',thinking:' second'}]}, {content:'answer'}],
  ['inline think tags', {content:'<think>first'}, {content:' second'}, {content:'</think>answer'}],
]) {
  test(`Worker delivers ${name} before upstream answer or completion`, async () => {
    let upstream;
    global.fetch = async () => response(new ReadableStream({start(c) { upstream=c; }}));
    const result = await worker.fetch(request());
    const reader = result.body.getReader();
    const next = async () => {
      const chunk = await bounded(reader.read());
      assert.equal(chunk.done, false);
      return new TextDecoder().decode(chunk.value);
    };
    try {
      // The worker loads history before opening the provider connection.
      while (!upstream) await new Promise(resolve => setImmediate(resolve));
      upstream.enqueue(encoder.encode(event(first)));
      assert.ok((await next()).includes('"type":"thinking","delta":"first"'));
      upstream.enqueue(encoder.encode(event(second)));
      assert.ok((await next()).includes('"type":"thinking","delta":" second"'));
      upstream.enqueue(encoder.encode(event(answer)+event({},'stop')+'data: [DONE]\n\n'));
      upstream.close();
      let remainder='';
      while (true) {
        const chunk=await bounded(reader.read());
        if(chunk.done) break;
        remainder+=new TextDecoder().decode(chunk.value);
      }
      assert.ok(remainder.includes('"type":"text","delta":"answer"'),remainder);
      assert.ok(remainder.includes('[DONE]'),remainder);
    } finally { await reader.cancel(); }
  });
}

test('diagnostic: reasoning_details-only deltas currently do not reach the thinking stream', async () => {
  global.fetch = async () => response(
    event({reasoning_details:[{type:'reasoning.text',text:'detail-only thought',index:0}]})+
    event({content:'answer'})+event({},'stop')+'data: [DONE]\n\n');
  const output=await bounded((await worker.fetch(request())).text());
  assert.ok(output.includes('"type":"text","delta":"answer"'),output);
  assert.ok(!output.includes('"type":"thinking"'),output);
  assert.equal(state.saves.at(-1).p_reasoning,'');
});
const encoder = new TextEncoder();
const event = (delta, finish = null) => 'data: ' + JSON.stringify({
  id: 'test', object: 'chat.completion.chunk', created: 1, model: 'test',
  choices: [{ index: 0, delta, finish_reason: finish }],
}) + '\n\n';
const body = (text) => new Response(text).body;
const request = (signal) => new Request('https://worker.test/v1/chat', {
  method: 'POST', signal,
  headers: { Authorization: 'Bearer user-token', 'X-AI-API-Key':'ai-key', 'Content-Type': 'application/json' },
  body: JSON.stringify({ conversationId:'10000000-0000-4000-8000-000000000001',requestId:'20000000-0000-4000-8000-000000000001',messageId:'30000000-0000-4000-8000-000000000001',prompt:'hello',model:'test' }),
});
const response = (text) => new Response(text, { headers: { 'Content-Type': 'text/event-stream' } });
const bounded = (promise) => Promise.race([
  promise,
  new Promise((_, reject) => { const timer = setTimeout(() => reject(new Error('Test timed out')), 2000); timer.unref(); }),
]);

test('normalizer preserves mixed reasoning and answer, including split UTF-8', async () => {
  const bytes = encoder.encode(event({ reasoning_content: 'คิด', content: 'คำตอบ' }) + 'data: [DONE]');
  let i = 0;
  const stream = new ReadableStream({ pull(c) {
    if (i === bytes.length) c.close(); else c.enqueue(bytes.slice(i, ++i));
  } });
  const output = await new Response(normalizeGatewayStream(stream)).text();
  assert.ok(output.includes('<think>คิด</think>คำตอบ'));
  assert.ok(output.includes('[DONE]'));
});

test('reasoning tag closes before DONE, including reasoning-only streams', async () => {
  const output = await new Response(normalizeGatewayStream(body(
    event({ reasoning_content: 'reasoning' }) + 'data: [DONE]\n\n'))).text();
  assert.ok(output.indexOf('</think>') < output.indexOf('[DONE]'));
});

test('upstream EOF without DONE is rejected', async () => {
  await assert.rejects(
    new Response(normalizeGatewayStream(body(event({ content: 'partial' })))).text(),
    /สิ้นสุดลงก่อนพบสัญญาณสิ้นสุดคำตอบ/,
  );
});

test('Worker sends both mixed fields through the real AI SDK', async () => {
  global.fetch = async () => response(event({ reasoning_content: 'reasoning', content: 'answer' }) + event({}, 'stop') + 'data: [DONE]\n\n');
  const result = await worker.fetch(request(), {});
  const text = await bounded(result.text());
  assert.ok(text.includes('"type":"thinking","delta":"reasoning"'), text);
  assert.ok(text.includes('"type":"text","delta":"answer"'), text);
  assert.ok(text.includes('[DONE]'), text);
  assert.ok(!text.includes('"type":"error"'), text);
  assert.equal(new Headers(state.aiHeaders).get('authorization'),'Bearer ai-key');
  assert.ok(!JSON.stringify(state.aiBody).includes('user-token'));
  assert.equal(state.aiBody.messages.at(-1).content,'database prompt');
  assert.ok(state.calls.every(c=>c.headers.Authorization==='Bearer user-token'&&c.headers.apikey==='publishable'));
  assert.equal(state.saves.at(-1).p_status,'completed');
  assert.equal(state.saves.at(-1).p_content,'answer');
});

test('missing and expired tokens never call AI',async()=>{
  const req=request(); req.headers.delete('Authorization');
  assert.equal((await worker.fetch(req)).status,401);
  assert.equal(state.upstream,0);
});
test('expired token is distinguished from gateway failure',async()=>{
  state.authError=true;
  const result=await worker.fetch(request());
  assert.equal(result.status,401);assert.equal((await result.json()).code,'AUTH_EXPIRED');assert.equal(state.upstream,0);
});
for(const code of ['ROOM_BUSY','ROOM_NOT_FOUND']) test(code+' cannot reach AI',async()=>{
  state.beginError=code;
  const result=await worker.fetch(request());
  assert.equal((await result.json()).code,code);assert.equal(state.upstream,0);
});
test('same request ID returns existing run without invoking AI',async()=>{
  state.started=false;
  const result=await worker.fetch(request());
  assert.equal(result.status,409);assert.equal((await result.json()).code,'REQUEST_EXISTS');assert.equal(state.upstream,0);assert.equal(state.saves.length,0);
});
test('unconfirmed save never sends successful DONE',async()=>{
  state.saveError=true;
  global.fetch=async()=>response(event({content:'answer'})+event({},'stop')+'data: [DONE]\n\n');
  const text=await bounded((await worker.fetch(request())).text());
  assert.ok(text.includes('SAVE_FAILED'));assert.ok(!text.includes('data: [DONE]'));
});
test('stop persists partial through authenticated RPC without an AI key',async()=>{
  const req=new Request('https://worker.test/v1/chat/20000000-0000-4000-8000-000000000001/stop',{
    method:'POST',headers:{Authorization:'Bearer user-token'},body:JSON.stringify({content:'partial',reasoning:'thought'})});
  assert.equal((await worker.fetch(req)).status,200);assert.equal(state.saves[0].p_status,'stopped');assert.equal(state.saves[0].p_content,'partial');assert.equal(state.upstream,0);
});
test('legacy unauthenticated API is closed',async()=>{
  const result=await actualWorker.fetch(new Request('https://worker.test/',{method:'POST',body:'{}'}),{});
  assert.equal(result.status,404);
});

test('Worker reports an upstream truncated stream without successful DONE', async () => {
  global.fetch = async () => response(event({ content: 'partial' }));
  const text = await bounded((await worker.fetch(request(), {})).text());
  assert.ok(text.includes('"type":"error"'), text);
  assert.ok(!text.includes('data: [DONE]'), text);
});

test('token limit finish is incomplete, not successful', async () => {
  global.fetch = async () => response(event({ content: 'partial' }) + event({}, 'length') + 'data: [DONE]\n\n');
  const text = await bounded((await worker.fetch(request(), {})).text());
  assert.ok(text.includes('"type":"error"'), text);
  assert.ok(!text.includes('data: [DONE]'), text);
});

test('response cancellation aborts the upstream fetch', async () => {
  let upstreamSignal;
  global.fetch = async (_, init) => {
    upstreamSignal = init.signal;
    return response(new ReadableStream({
      start(c) {
        c.enqueue(encoder.encode(event({ content: 'partial' })));
        init.signal.addEventListener('abort', () => c.error(new DOMException('Aborted', 'AbortError')), { once: true });
      },
    }));
  };
  const result = await worker.fetch(request(), {});
  const reader = result.body.getReader();
  await bounded(reader.read());
  await bounded(reader.cancel('Stop'));
  assert.equal(upstreamSignal.aborted, true);
});

test('incoming request abort propagates while waiting for the first token', async () => {
  let started;
  const ready = new Promise(resolve => { started = resolve; });
  let upstreamSignal;
  global.fetch = (_, init) => new Promise((_, reject) => {
    upstreamSignal = init.signal;
    init.signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')), { once: true });
    started();
  });
  const abort = new AbortController();
  const result = await worker.fetch(request(abort.signal), {});
  const reading = result.text();
  await ready;
  abort.abort();
  await bounded(reading);
  assert.equal(upstreamSignal.aborted, true);
});

test('normalizer extracts reasoning from thinking field (Claude 3.7 / OpenRouter style)', async () => {
  const output = await new Response(normalizeGatewayStream(body(
    event({ thinking: 'Claude thinking...', content: 'Claude answer' }) + 'data: [DONE]\n\n'
  ))).text();
  assert.ok(output.includes('<think>Claude thinking...</think>Claude answer'), output);
});

test('normalizer extracts reasoning from thoughts, thought_content, and reasoning_text', async () => {
  const output1 = await new Response(normalizeGatewayStream(body(
    event({ thoughts: 'Gemini thoughts' }) + 'data: [DONE]\n\n'
  ))).text();
  assert.ok(output1.includes('<think>Gemini thoughts'), output1);
  assert.ok(output1.includes('</think>'), output1);

  const output2 = await new Response(normalizeGatewayStream(body(
    event({ thought_content: 'Qwen thought' }) + 'data: [DONE]\n\n'
  ))).text();
  assert.ok(output2.includes('<think>Qwen thought'), output2);
  assert.ok(output2.includes('</think>'), output2);

  const output3 = await new Response(normalizeGatewayStream(body(
    event({ reasoning_text: 'Proxy reasoning' }) + 'data: [DONE]\n\n'
  ))).text();
  assert.ok(output3.includes('<think>Proxy reasoning'), output3);
  assert.ok(output3.includes('</think>'), output3);
});

test('normalizer extracts reasoning from objects, arrays, and content block lists', async () => {
  // Object reasoning
  const outputObj = await new Response(normalizeGatewayStream(body(
    event({ thinking: { text: 'Object thinking' }, content: 'Answer' }) + 'data: [DONE]\n\n'
  ))).text();
  assert.ok(outputObj.includes('<think>Object thinking</think>Answer'), outputObj);

  // Content block array
  const outputBlocks = await new Response(normalizeGatewayStream(body(
    event({
      content: [
        { type: 'thinking', thinking: 'Block thought' },
        { type: 'text', text: 'Block answer' },
      ],
    }) + 'data: [DONE]\n\n'
  ))).text();
  assert.ok(outputBlocks.includes('<think>Block thought</think>Block answer'), outputBlocks);
});

test('normalizer extracts reasoning from message property and root level', async () => {
  const msgEvent = 'data: ' + JSON.stringify({
    id: 'test', object: 'chat.completion.chunk', created: 1, model: 'test',
    choices: [{ index: 0, message: { reasoning_content: 'Message reasoning', content: 'Message content' } }],
  }) + '\n\n';
  const outputMsg = await new Response(normalizeGatewayStream(body(msgEvent + 'data: [DONE]\n\n'))).text();
  assert.ok(outputMsg.includes('<think>Message reasoning</think>Message content'), outputMsg);

  const rootEvent = 'data: ' + JSON.stringify({
    id: 'test', object: 'chat.completion.chunk', created: 1, model: 'test',
    reasoning: 'Root reasoning',
    choices: [{ index: 0, delta: { content: 'Root content' } }],
  }) + '\n\n';
  const outputRoot = await new Response(normalizeGatewayStream(body(rootEvent + 'data: [DONE]\n\n'))).text();
  assert.ok(outputRoot.includes('<think>Root reasoning</think>Root content'), outputRoot);
});
