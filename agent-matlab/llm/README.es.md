# llm/

> English: [README.md](README.md)

Comunicación con LM Studio (compatible con OpenAI, `webwrite`).

| Archivo | Función |
|---|---|
| `send_input_llm.m` | `[response, port_used] = send_input_llm(cfg, prompt, payload, img_path)`. Abstracción de puertos, transporte (`http`/`mock`), failover |
| `build_request_body.m` | Construye el cuerpo JSON: system + [few-shot] + user con `text` e `image_url` (data URI PNG) |
| `parse_llm_response.m` | Extrae el JSON y lo repara: `<think>`, cercas markdown, `}` faltante (la elimina el stop token) |
| `is_valid_response.m` | Validación estricta: campos, lista cerrada de comandos, coherencia command/finger/action, canales 1–8, value entero dentro del rango |
| `llm_logger.m` | `logs/llm_YYYYMMDD_HHMMSS.jsonl`, una línea por ciclo, más un resumen con recuento por puerto |

## Modos de puertos (`server_llm.mode`)

| Modo | N = 1 | N = 4 |
|---|---|---|
| `sequential` | 1234 | siempre empieza en 1234; si falla rápido, prueba 1235, 1236, … |
| `round-robin` | 1234 | 1234 → 1235 → 1236 → 1237 → 1234 … (+ failover) |
| `parallel` (experimental) | igual que sequential | envía a todos los puertos con `backgroundPool` y se queda con la primera respuesta; si `webwrite` no funciona en hilos, pasa a `sequential` automáticamente |

Todos los reintentos comparten **un único presupuesto de tiempo por ciclo**
(`cycle_budget`, que por defecto vale `timeout`). Por eso un timeout nunca multiplica la
latencia por N.

El camino de código es **el mismo** para N = 1 y N = 4. Solo cambia
`config/server-llm.mat`. `tests/test_parallel_ports.m` lo comprueba.

## Contrato de respuesta

```json
{"command":"B","finger":"D2","action":"flex","confidence":0.92,"trigger_channels":[4,7],"value":95}
```

Cualquier fallo (error HTTP, timeout, sin JSON, JSON inválido o campos incoherentes) hace
que `main.m` use el fallback LDA **solo en ese ciclo**. En el siguiente ciclo se vuelve a
llamar al LLM.

## Transporte `mock`

Es un clasificador determinista que implementa las reglas del prompt. Permite probar el
pipeline y el reparto de puertos sin red, por el mismo camino de código.
`mock_fail_ports` simula puertos caídos.
