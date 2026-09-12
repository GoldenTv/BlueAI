/**
 * Preserve both fields when a gateway sends reasoning and answer together.
 * Normalizes reasoning from all known fields into <think>...</think> tags.
 */

const REASONING_KEYS = [
  'reasoning_content',
  'reasoning',
  'thinking',
  'thought',
  'thoughts',
  'thought_content',
  'reasoning_text',
  'reason',
] as const;

function extractText(val: unknown): string {
  if (typeof val === 'string') return val;
  if (!val) return '';
  if (Array.isArray(val)) {
    return val.map(extractText).filter(Boolean).join('');
  }
  if (typeof val === 'object') {
    const obj = val as Record<string, unknown>;
    if (typeof obj.text === 'string') return obj.text;
    if (typeof obj.content === 'string') return obj.content;
    if (typeof obj.thinking === 'string') return obj.thinking;
    if (typeof obj.thought === 'string') return obj.thought;
    if (typeof obj.value === 'string') return obj.value;
  }
  return '';
}

function extractReasoningFromRecord(rec: Record<string, unknown> | null | undefined): string {
  if (!rec || typeof rec !== 'object') return '';
  let res = '';
  for (const key of REASONING_KEYS) {
    if (key in rec && rec[key] != null) {
      const text = extractText(rec[key]);
      if (text) res += text;
    }
  }
  return res;
}

function cleanReasoningKeys(rec: Record<string, unknown> | null | undefined): void {
  if (!rec || typeof rec !== 'object') return;
  for (const key of REASONING_KEYS) {
    if (key in rec) {
      delete rec[key];
    }
  }
}

function extractFromContentArray(content: unknown[]): { text: string; reasoning: string } {
  let text = '';
  let reasoning = '';
  for (const block of content) {
    if (typeof block === 'string') {
      text += block;
    } else if (block && typeof block === 'object') {
      const b = block as Record<string, unknown>;
      const bType = typeof b.type === 'string' ? b.type.toLowerCase() : '';
      if (bType === 'thinking' || bType === 'reasoning' || bType === 'thought') {
        reasoning += extractText(b.thinking ?? b.reasoning ?? b.thought ?? b.text ?? b.content);
      } else {
        const blockReasoning = extractReasoningFromRecord(b);
        if (blockReasoning) reasoning += blockReasoning;
        const blockText = typeof b.text === 'string' ? b.text : (typeof b.content === 'string' ? b.content : '');
        if (blockText) text += blockText;
      }
    }
  }
  return { text, reasoning };
}

export function normalizeGatewayStream(body: ReadableStream<Uint8Array>): ReadableStream<Uint8Array> {
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let buffer = '';
  let inReasoning = false;
  let completed = false;

  function line(raw: string, controller: TransformStreamDefaultController<Uint8Array>) {
    const value = raw.trim();
    if (completed) return;
    if (!value.startsWith('data:')) {
      controller.enqueue(encoder.encode(raw + '\n'));
      return;
    }
    const data = value.slice(5).trim();
    if (data === '[DONE]') {
      if (inReasoning) {
        controller.enqueue(encoder.encode('data: {"choices":[{"index":0,"delta":{"content":"</think>"}}]}\n\n'));
        inReasoning = false;
      }
      completed = true;
      controller.enqueue(encoder.encode('data: [DONE]\n\n'));
      return;
    }
    if (!data) return;

    let parsed: any;
    try {
      parsed = JSON.parse(data);
    } catch {
      controller.enqueue(encoder.encode(raw + '\n'));
      return;
    }

    const choice = parsed?.choices?.[0];
    if (choice) {
      if (!choice.delta) {
        choice.delta = choice.message ?? {};
      }
      const delta = choice.delta;

      let reasoning = '';
      let answer = '';

      if (Array.isArray(delta.content)) {
        const extracted = extractFromContentArray(delta.content);
        reasoning += extracted.reasoning;
        answer += extracted.text;
      } else if (typeof delta.content === 'string') {
        answer += delta.content;
      } else if (typeof delta.text === 'string') {
        answer += delta.text;
      }

      reasoning += extractReasoningFromRecord(delta);
      cleanReasoningKeys(delta);

      reasoning += extractReasoningFromRecord(choice);
      cleanReasoningKeys(choice);

      reasoning += extractReasoningFromRecord(parsed);
      cleanReasoningKeys(parsed);

      let content = '';
      if (reasoning) {
        content += (inReasoning ? '' : '<think>') + reasoning;
        inReasoning = true;
      }
      if (answer || choice.finish_reason != null) {
        if (inReasoning) content += '</think>';
        inReasoning = false;
        content += answer;
      }
      if (content || !('content' in delta)) {
        delta.content = content;
      }
    }

    controller.enqueue(encoder.encode(`data: ${JSON.stringify(parsed)}\n`));
  }

  return body.pipeThrough(new TransformStream<Uint8Array, Uint8Array>({
    transform(chunk, controller) {
      buffer += decoder.decode(chunk, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() ?? '';
      for (const raw of lines) line(raw, controller);
      if (completed) controller.terminate();
    },
    flush(controller) {
      buffer += decoder.decode();
      if (buffer.trim()) line(buffer, controller);
      if (!completed) throw new Error('การสตรีมข้อมูลจาก Gateway สิ้นสุดลงก่อนพบสัญญาณสิ้นสุดคำตอบ');
    },
  }));
}
