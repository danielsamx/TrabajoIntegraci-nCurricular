# Changelog / Historial de cambios

All notable changes to this project are documented here.
Todos los cambios relevantes del proyecto se documentan aquí.

Format based on [Keep a Changelog](https://keepachangelog.com/) · Versioning:
[SemVer](https://semver.org/).

## [1.0.0] - 2026-09-16

### Added / Añadido
- Real-time loop `main.m` with a **mandatory LLM call on every cycle** (TEXT + IMAGE),
  validation, emergency LDA fallback, temporal smoothing and HTTP delivery to the prosthesis.
  / Bucle en tiempo real `main.m` con **invocación obligatoria del LLM en cada ciclo**
  (TEXTO + IMAGEN), validación, fallback LDA de emergencia, suavizado temporal y envío HTTP a
  la prótesis.
- `main_debug.m`: live dashboard (EMG, RMS, latencies, decision source, VLM image).
  / Panel en vivo (EMG, RMS, latencias, origen de la decisión, imagen del VLM).
- Port abstraction in `send_input_llm.m`: `sequential`, `round-robin`, experimental
  `parallel` (`backgroundPool`) and failover, all driven by `config/server-llm.mat` (N=1 ↔ N=4).
  / Abstracción de puertos en `send_input_llm.m`: `sequential`, `round-robin`, `parallel`
  experimental y failover; todo controlado por `config/server-llm.mat` (N=1 ↔ N=4).
- `myo_interface.m`: native BLE Myo protocol with MATLAB `ble()`, a UDP source, a simulated
  source and a circular buffer. / Protocolo BLE nativo del Myo con `ble()`, fuente UDP,
  fuente simulada y buffer circular.
- Per-user calibration (`calibrate.m`) with rest/MVC normalization, finger profiles, dominant
  channels (`CALIB`) and LDA cross-validation. / Calibración por usuario con normalización
  reposo/MVC, perfiles por dedo, canales dominantes (`CALIB`) y validación cruzada del LDA.
- Bilingual system prompts (`prompts/system_es.txt`, `prompts/system_en.txt`), 10 few-shot
  examples and a calibration template. / System prompts bilingües, 10 ejemplos few-shot y
  plantilla de calibración.
- Prosthesis simulator (in-process `SIM` and HTTP server over `tcpserver`).
  / Simulador de prótesis (`SIM` en proceso y servidor HTTP sobre `tcpserver`).
- Standalone tests: `test_payload`, `test_llm_connection`, `test_prosthesis_connection`,
  `test_full_pipeline`, `test_parallel_ports`. / Pruebas independientes.
- Bilingual documentation (README, per-module READMEs, `docs/`).
  / Documentación bilingüe.

### Notes / Notas
- Function files use underscores instead of the hyphens in the original spec, because MATLAB
  cannot call hyphenated function names. / Los archivos de función usan guion bajo en vez de
  guion porque MATLAB no puede llamar funciones con guiones.
