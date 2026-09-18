# tests/

> Español: [README.es.md](README.es.md)

Every test is a function you can run on its own. It adds the project paths itself, prints
`[PASS]` / `[FAIL]` for each check, and returns `true` or `false`.

| Test | Needs a network? | What it checks |
|---|---|---|
| `test_payload` | No | Exact payload format, clipping, PREV/CALIB, ASCII. The 10 prompt examples are valid, and their `value` and gesture match `rms_to_value` / `is_composite_gesture`. JSON repair. Validator rejections |
| `test_parallel_ports` | No (`mock`) | N=1 → always 1234. N=4 round-robin → 1234..1237. Sequential mode. Failover when 1235 is down. All ports down → `ok=false`. **`main` with N=1 and N=4 produces the same command sequence** (6 calls per port with N=4) |
| `test_full_pipeline` | No | `main` end to end with the simulated Myo, the SIM prosthesis and (A) the `mock` LLM: 40 cycles, 40 LLM calls, 0 fallbacks, REST→`#R`, D2→`B`, D3→`C`. (B) LLM unreachable: LLM still called every cycle, 100 % LDA fallback, D2→`B` |
| `test_llm_connection` | **Yes** (LM Studio) | `GET /v1/models` plus 2 real TEXT+IMAGE classifications on each port, latency, and a warning if the warm latency is above `timeout` |
| `test_prosthesis_connection` | **Yes** (or SIM) | Sends `#R`. With `'Sweep', true`, moves each finger to 30° and back |

```matlab
ok = test_payload();
ok = test_parallel_ports();
ok = test_full_pipeline();
ok = test_llm_connection('Timeout', 60);
ok = test_prosthesis_connection('Sweep', true);
```

The tests **do not modify** `config/*.mat`. They inject in-memory configurations into
`main` (`'LlmConfig'`, `'ProsthesisConfig'`, …) and write logs to
`tempdir/protesis_test_logs`.

To run everything:

```matlab
results = [test_payload, test_parallel_ports, test_full_pipeline, ...
           test_llm_connection, test_prosthesis_connection]
```
