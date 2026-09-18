# config/

> English: [README.md](README.md)

Generadores de los cuatro archivos `.mat` de configuración. Los `.mat` los **genera**
`setup.m` y git los ignora, porque contienen IPs y datos del usuario.

| Archivo | Genera | Variable |
|---|---|---|
| `create_server_llm_config.m` | `server-llm.mat` | `server_llm` |
| `create_server_prosthesis_config.m` | `server-prosthesis.mat` | `server_prosthesis` |
| `create_prompt_llm_config.m` | `prompt-llm.mat` | `prompt_llm` |
| `create_calibration_config.m` | `calibration.mat` (genérica, `is_default = true`) | `calib` |

Todos los generadores aceptan **pares nombre-valor** que sobrescriben cualquier campo. No
edite un `.mat` a mano; regénérelo.

```matlab
create_server_llm_config('ip', '192.168.1.50');                        % N = 1
create_server_llm_config('ports', [1234 1235 1236 1237], 'mode', 'round-robin'); % N = 4
create_server_llm_config('timeout', 1.5);
create_server_prosthesis_config('ip', '192.168.1.77');
create_server_prosthesis_config('protocol', 'SIM');                     % simulador
create_prompt_llm_config('language', 'en');
create_prompt_llm_config('render_mode', 'raster', 'image_width', 320, 'image_height', 240);
create_calibration_config('Overwrite', true);                           % calibración genérica
```

## `server_llm`

| Campo | Defecto | Notas |
|---|---|---|
| `ip` | `'192.168.1.100'` | Host de LM Studio |
| `ips` | `{}` | Opcional, una IP por puerto |
| `endpoint` | `'/v1/chat/completions'` | Compatible con OpenAI |
| `api_key` | `'lm-studio'` | Se envía como `Authorization: Bearer` |
| `timeout` | `0.5` | Presupuesto del LLM por ciclo (s) |
| `cycle_budget` | `[]` | `[]` = igual a `timeout` |
| `max_tokens` / `temperature` / `top_p` | `200` / `0` / `1` | Salida determinista |
| `stop` | `}` LF, `}` CR LF, LF LF | Saltos de línea reales, no el literal `\n` |
| `use_json_schema` | `false` | `response_format` json_schema |
| `ports` | `1234` | **Cambie solo esto para pasar de N=1 a N=4** |
| `models` | `{'qwen2.5-vl-7b-instruct'}` | 1 compartido o 1 por puerto |
| `mode` | `'sequential'` | `sequential`, `round-robin`, `parallel` |
| `transport` | `'http'` | `mock` para pruebas sin red |

## `server_prosthesis`

`ip`, `port` (8080), `endpoint` (`/api/command`), `timeout` (0.5), `protocol`
(`HTTP` o `SIM`), `max_consecutive_failures` (5), `safe_command` (`#R`).

## `prompt_llm`

`language`, `system_prompt`, `few_shot`, `use_few_shot_messages` (false),
`calibration_template`, `system_prompt_effective` (lo rellena `main.m`), `image`
(`width`, `height`, `render_mode`), `created`, `source_files`.

## `calib`

Vea [../docs/calibration_guide.es.md](../docs/calibration_guide.es.md).
