# prompts/

> Español: [README.es.md](README.es.md)

The text sources of the LLM prompt. `create_prompt_llm_config` compiles them into
`config/prompt-llm.mat`. **After editing a `.txt`, run the generator again.**

| File | Content |
|---|---|
| `system_es.txt` | Spanish system prompt (default) |
| `system_en.txt` | Full English translation |
| `few_shot_examples.jsonl` | The same 10 examples as the prompt, one JSON per line (`id`, `description_es`, `description_en`, `input`, `output`) |
| `calibration_template.txt` | `### ES` / `### EN` blocks with the `{{USER_ID}}`, `{{CALIB_DATE}}`, `{{IS_DEFAULT}}`, `{{CV_ACCURACY}}`, `{{TOP_CHANNELS}}` and `{{PROFILE_TABLE}}` placeholders. `main.m` fills them in once at startup |

## System prompt sections

1. Role: deterministic, low-latency classifier
2. Absolute rules (a single JSON line, no markdown, no explanations)
3. Anatomical map of the 8 Myo channels (reference placement)
4. Finger table A–F with range limits
5. Preset gestures `#O #C #P #R #W #Y #L #M #H #U #G`
6. Levels (0.15 / 0.25 / 0.40)
7. Spatial recognition rules R1–R8, in priority order
8. Composite gesture rules G1–G10
9. Input format (RMS, MAV, STATE, CALIB, PREV, T + image description)
10. Output format and mandatory consistency
11. Value rules
12. Confidence ranges
13. 10 examples

## Consistency contract

The rules in the prompt are implemented **identically** in `utils/is_composite_gesture.m`
and `utils/rms_to_value.m`, which the LDA fallback and the `mock` transport use.
`tests/test_payload.m` checks that every example in `few_shot_examples.jsonl` passes the
validator and that its `value` and gesture match the code. **If you change a rule in the
prompt, change it in the code as well** (and the other way round).

## Why the system prompt stays fixed

The system prompt is identical in every request, so LM Studio reuses the KV cache of the
prefix. The user calibration is appended once when `main.m` starts.
