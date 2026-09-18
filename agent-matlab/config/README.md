# config/

> Español: [README.es.md](README.es.md)

Generators for the four `.mat` configuration files. The `.mat` files are **generated** by
`setup.m` and ignored by git, because they contain IPs and user data.

| File | Generates | Variable |
|---|---|---|
| `create_server_llm_config.m` | `server-llm.mat` | `server_llm` |
| `create_server_prosthesis_config.m` | `server-prosthesis.mat` | `server_prosthesis` |
| `create_prompt_llm_config.m` | `prompt-llm.mat` | `prompt_llm` |
| `create_calibration_config.m` | `calibration.mat` (generic, `is_default = true`) | `calib` |

Every generator takes **name-value pairs** that override any field. Do not edit a `.mat` by
hand; regenerate it.

```matlab
create_server_llm_config('ip', '192.168.1.50');                        % N = 1
create_server_llm_config('ports', [1234 1235 1236 1237], 'mode', 'round-robin'); % N = 4
create_server_llm_config('timeout', 1.5);
create_server_prosthesis_config('ip', '192.168.1.77');
create_server_prosthesis_config('protocol', 'SIM');                     % simulator
create_prompt_llm_config('language', 'en');
create_prompt_llm_config('render_mode', 'raster', 'image_width', 320, 'image_height', 240);
create_calibration_config('Overwrite', true);                           % generic calibration
```

## `server_llm`

| Field | Default | Notes |
|---|---|---|
| `ip` | `'192.168.1.100'` | LM Studio host |
| `ips` | `{}` | Optional, one IP per port |
| `endpoint` | `'/v1/chat/completions'` | OpenAI-compatible |
| `api_key` | `'lm-studio'` | Sent as `Authorization: Bearer` |
| `timeout` | `0.5` | Per-cycle LLM budget (s) |
| `cycle_budget` | `[]` | `[]` = same as `timeout` |
| `max_tokens` / `temperature` / `top_p` | `200` / `0` / `1` | Deterministic output |
| `stop` | `}` LF, `}` CR LF, LF LF | Real line breaks, not the literal `\n` |
| `use_json_schema` | `false` | `response_format` json_schema |
| `ports` | `1234` | **Change only this to go from N=1 to N=4** |
| `models` | `{'qwen2.5-vl-7b-instruct'}` | 1 shared or 1 per port |
| `mode` | `'sequential'` | `sequential`, `round-robin`, `parallel` |
| `transport` | `'http'` | `mock` for offline tests |

## `server_prosthesis`

`ip`, `port` (8080), `endpoint` (`/api/command`), `timeout` (0.5), `protocol`
(`HTTP` or `SIM`), `max_consecutive_failures` (5), `safe_command` (`#R`).

## `prompt_llm`

`language`, `system_prompt`, `few_shot`, `use_few_shot_messages` (false),
`calibration_template`, `system_prompt_effective` (filled in by `main.m`), `image`
(`width`, `height`, `render_mode`), `created`, `source_files`.

## `calib`

See [../docs/calibration_guide.md](../docs/calibration_guide.md).
