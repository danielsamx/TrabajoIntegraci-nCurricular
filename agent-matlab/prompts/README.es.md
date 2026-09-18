# prompts/

> English: [README.md](README.md)

Fuentes de texto del prompt del LLM. `create_prompt_llm_config` las compila en
`config/prompt-llm.mat`. **Después de editar un `.txt`, vuelva a ejecutar el generador.**

| Archivo | Contenido |
|---|---|
| `system_es.txt` | System prompt en español (por defecto) |
| `system_en.txt` | Traducción completa al inglés |
| `few_shot_examples.jsonl` | Los mismos 10 ejemplos del prompt, un JSON por línea (`id`, `description_es`, `description_en`, `input`, `output`) |
| `calibration_template.txt` | Bloques `### ES` / `### EN` con los marcadores `{{USER_ID}}`, `{{CALIB_DATE}}`, `{{IS_DEFAULT}}`, `{{CV_ACCURACY}}`, `{{TOP_CHANNELS}}` y `{{PROFILE_TABLE}}`. `main.m` los rellena una vez al arrancar |

## Secciones del system prompt

1. Rol: clasificador determinista de baja latencia
2. Reglas absolutas (una sola línea JSON, sin markdown, sin explicaciones)
3. Mapa anatómico de los 8 canales del Myo (colocación de referencia)
4. Tabla de dedos A–F con límites de recorrido
5. Gestos preestablecidos `#O #C #P #R #W #Y #L #M #H #U #G`
6. Niveles (0.15 / 0.25 / 0.40)
7. Reglas de reconocimiento espacial R1–R8, en orden de prioridad
8. Reglas de gestos compuestos G1–G10
9. Formato de entrada (RMS, MAV, STATE, CALIB, PREV, T + descripción de la imagen)
10. Formato de salida y coherencia obligatoria
11. Reglas de value
12. Rangos de confidence
13. 10 ejemplos

## Contrato de coherencia

Las reglas del prompt están implementadas **igual** en `utils/is_composite_gesture.m` y
`utils/rms_to_value.m`, que usan el fallback LDA y el transporte `mock`.
`tests/test_payload.m` comprueba que cada ejemplo de `few_shot_examples.jsonl` pasa el
validador y que su `value` y su gesto coinciden con el código. **Si cambia una regla en el
prompt, cámbiela también en el código** (y al revés).

## Por qué el system prompt no cambia

El system prompt es idéntico en todas las peticiones, así que LM Studio reutiliza la caché KV
del prefijo. La calibración del usuario se añade una sola vez al arrancar `main.m`.
