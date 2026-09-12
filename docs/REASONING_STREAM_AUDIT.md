# Reasoning stream audit — 2026-09-12

## Scope and evidence

Reported model: `gpt-5.6-luna`. The thinking timer advances, then visible
reasoning arrives as a block before the answer streams. No live gateway capture
or affected-device profile was available. Findings below distinguish reproducible
local behavior from hypotheses about the provider. Production code was not changed.

## Data path

Gateway chat/completions SSE → normalizeGatewayStream → installed AI SDK
extractReasoningMiddleware → Worker thinking/text SSE → AiGatewayService →
CloudChatController (85 ms notification batching) → ThinkingIndicator.

The Worker saves database snapshots every 2 seconds, but emits live deltas without
waiting for these checkpoints. Another device watching database updates can see
coarser updates; the initiating controller uses its local streaming answer.

## Confirmed findings

1. There is no wait-for-closing-think-tag requirement in the installed streaming
   middleware. Four gated tests hold the upstream open and verify that two separate
   reasoning deltas reach the Worker response before any answer or completion:
   reasoning_content, thinking, content blocks, and inline think tags.
2. Flutter transport and CloudChatController notify listeners with successive
   reasoning values while the answer is empty and the request is still loading.
   The expanded thinking widget updates while thinking and remains expanded when
   its state changes to completed thinking.
3. `reasoning_details` is absent from both parser key lists. A synthetic event
   containing only reasoning_details yields an answer but no thinking event or
   saved reasoning through the actual Worker/SDK. This is a confirmed compatibility
   gap, not proof that the reported model uses that field.
4. The thinking panel is collapsed by default. Text is rendered only after the
   user expands it and reasoning is nonempty. Opening it late reveals accumulated
   text at once; this does not prove transport buffering.
5. The client timer starts before the gateway request and stops on the first
   nonempty answer text. The server measures from stream setup to first answer.
   These are time-to-first-answer approximations, including network/provider delay,
   not provider-reported internal reasoning duration. Whitespace also counts as
   nonempty in the current implementation.
6. The request uses generic streamText and a prompt allowing think tags; it does
   not explicitly configure per-model reasoning effort, thinking budget, or summary
   output. A prompt cannot guarantee provider reasoning streaming behavior.
7. A 90-second idle timeout exists. If no usable events arrive during a long quiet
   reasoning period, the request can be interrupted. This is distinct from normal
   stopping of the thinking timer when the answer begins.

## What would distinguish the remaining causes

Capture metadata for one affected request at gateway ingress, Worker SSE egress,
and Flutter callback: elapsed milliseconds, event field names, and text/reasoning
lengths only. Do not log tokens, credentials, prompts, or reasoning bodies.

- First gateway reasoning event is already large and late: upstream/provider
  batching or summary delivery; frontend cannot render data before receiving it.
- Early reasoning_details events, followed by a late legacy reasoning field:
  normalizer compatibility gap can explain the observed late block.
- Gateway events are incremental but Worker output is late: inspect real framing,
  content type, proxy transport, and SDK handling for that payload.
- Worker output is incremental but Flutter receives a batch: inspect transport.
- Flutter callbacks are incremental but screen is late: profile Markdown layout
  and check collapsed state on the affected device.

Model aliases at a gateway do not establish which underlying API/model is used.
Do not attribute the behavior specifically to GPT or a provider without a capture.

## Validation

- `node --test tests/stream.test.cjs`: 25 passed, including 5 new diagnostic tests.
- `flutter test --no-pub test/cloud_chat_test.dart test/thinking_indicator_test.dart test/stream_reliability_test.dart`: 24 passed, including 2 new incremental-update tests.
- No deployment, live model call, or production behavior change performed.

## References

- https://openrouter.ai/docs/guides/best-practices/reasoning-tokens
  documents streamed reasoning_details and the distinction between text, summary,
  and encrypted entries. This is an example supported protocol, not confirmation
  that the configured gateway uses OpenRouter.
- Relevant source: backend/src/gateway-stream.ts, backend/src/index.ts,
  lib/src/ai_gateway_service.dart, lib/src/cloud_chat_controller.dart,
  lib/src/chat_page.dart, lib/src/chat_widgets.dart.
