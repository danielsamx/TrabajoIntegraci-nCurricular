# llm/

> Español: [README.es.md](README.es.md)

LM Studio communication (OpenAI-compatible, `webwrite`).

| File | Role |
|---|---|
| `send_input_llm.m` | `[response, port_used] = send_input_llm(cfg, prompt, payload, img_path)`. Port abstraction, transport (`http`/`mock`), failover |
| `build_request_body.m` | Builds the JSON body: system + [few-shot] + user with `text` and `image_url` (PNG data URI) |
| `parse_llm_response.m` | Extracts the JSON and repairs it: `<think>`, markdown fences, a missing `}` (removed by the stop token) |
| `is_valid_response.m` | Strict validation: fields, closed command list, command/finger/action consistency, channels 1–8, integer value within range |
| `llm_logger.m` | `logs/llm_YYYYMMDD_HHMMSS.jsonl`, one line per cycle, plus a summary with per-port counts |

## Port modes (`server_llm.mode`)

| Mode | N = 1 | N = 4 |
|---|---|---|
| `sequential` | 1234 | always starts at 1234; if it fails fast, tries 1235, 1236, … |
| `round-robin` | 1234 | 1234 → 1235 → 1236 → 1237 → 1234 … (+ failover) |
| `parallel` (experimental) | same as sequential | sends to all ports with `backgroundPool` and keeps the first answer; if `webwrite` is not supported in threads, it switches to `sequential` automatically |

All retries share **one time budget per cycle** (`cycle_budget`, which defaults to
`timeout`). A timeout therefore never multiplies the latency by N.

The code path is **the same** for N = 1 and N = 4. Only `config/server-llm.mat` changes.
`tests/test_parallel_ports.m` checks this.

## Response contract

```json
{"command":"B","finger":"D2","action":"flex","confidence":0.92,"trigger_channels":[4,7],"value":95}
```

Any failure (HTTP error, timeout, no JSON, invalid JSON, inconsistent fields) makes
`main.m` use the LDA fallback **for that cycle only**. The LLM is called again on the next
cycle.

## `mock` transport

This is a deterministic classifier that implements the prompt rules. It lets you test the
pipeline and the port distribution without a network, through the same code path.
`mock_fail_ports` simulates ports that are down.
