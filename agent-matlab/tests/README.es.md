# tests/

> English: [README.md](README.md)

Cada prueba es una función que se puede ejecutar por separado. Añade por sí misma las rutas
del proyecto, imprime `[PASS]` / `[FAIL]` en cada comprobación y devuelve `true` o `false`.

| Prueba | ¿Necesita red? | Qué comprueba |
|---|---|---|
| `test_payload` | No | Formato exacto del payload, recorte, PREV/CALIB, ASCII. Los 10 ejemplos del prompt son válidos, y su `value` y su gesto coinciden con `rms_to_value` / `is_composite_gesture`. Reparación de JSON. Rechazos del validador |
| `test_parallel_ports` | No (`mock`) | N=1 → siempre 1234. N=4 round-robin → 1234..1237. Modo secuencial. Failover con 1235 caído. Todos los puertos caídos → `ok=false`. **`main` con N=1 y N=4 produce la misma secuencia de comandos** (6 llamadas por puerto con N=4) |
| `test_full_pipeline` | No | `main` de extremo a extremo con Myo simulado, prótesis SIM y (A) LLM `mock`: 40 ciclos, 40 llamadas al LLM, 0 fallbacks, REST→`#R`, D2→`B`, D3→`C`. (B) LLM inalcanzable: el LLM se sigue llamando en cada ciclo, 100 % fallback LDA, D2→`B` |
| `test_llm_connection` | **Sí** (LM Studio) | `GET /v1/models` más 2 clasificaciones reales TEXTO+IMAGEN en cada puerto, latencia, y un aviso si la latencia en caliente supera `timeout` |
| `test_prosthesis_connection` | **Sí** (o SIM) | Envía `#R`. Con `'Sweep', true`, mueve cada dedo a 30° y lo devuelve |

```matlab
ok = test_payload();
ok = test_parallel_ports();
ok = test_full_pipeline();
ok = test_llm_connection('Timeout', 60);
ok = test_prosthesis_connection('Sweep', true);
```

Las pruebas **no modifican** `config/*.mat`. Inyectan configuraciones en memoria en `main`
(`'LlmConfig'`, `'ProsthesisConfig'`, …) y escriben los logs en
`tempdir/protesis_test_logs`.

Para ejecutarlo todo:

```matlab
results = [test_payload, test_parallel_ports, test_full_pipeline, ...
           test_llm_connection, test_prosthesis_connection]
```
