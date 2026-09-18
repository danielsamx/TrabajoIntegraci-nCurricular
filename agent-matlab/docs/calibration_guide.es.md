# Guía de calibración

> English: [calibration_guide.md](calibration_guide.md)

La calibración adapta el sistema a cada persona: piel, grasa, tamaño del músculo y, sobre
todo, **dónde queda el brazalete**. Calibre al inicio de cada sesión y cada vez que se quite
el brazalete.

## 1. Preparación

1. Limpie la piel del antebrazo (seca, sin crema).
2. Coloque el Myo en el **antebrazo derecho**, a un tercio de la distancia desde el codo,
   con el **puerto USB hacia la muñeca**.
3. Colocación de referencia: **CH1 sobre el flexor cubital del carpo** (palma hacia arriba,
   lado del meñique). Los canales rodean la cara palmar hacia el pulgar (CH5) y vuelven por
   el dorso (CH6–CH8).

   | Canal | Músculo (referencia) | Dedo |
   |---|---|---|
   | CH1 | Flexor cubital del carpo | Flexión D5 |
   | CH2 | Flexor superficial de los dedos (cubital) | Flexión D4 |
   | CH3 | Flexor superficial de los dedos (central) | Flexión D3 |
   | CH4 | Flexor superficial/profundo (radial) | Flexión D2 |
   | CH5 | Flexor largo del pulgar / flexor radial del carpo | Flexión D1 |
   | CH6 | Abductor largo / extensores del pulgar | Extensión D1 |
   | CH7 | Extensor común de los dedos + extensor del índice | Extensión D2–D3 |
   | CH8 | Extensor del meñique + extensor cubital del carpo | Extensión D4–D5 |

   La colocación exacta **no** tiene que ser perfecta. La calibración mide los canales
   dominantes reales y los envía al LLM en `CALIB`, que tiene prioridad sobre esta tabla.
4. Espere **2–3 minutos** para que se estabilice el contacto piel–electrodo (el Myo se
   calienta).
5. Siéntese con el codo apoyado en la mesa y el antebrazo relajado.

## 2. Ejecución de la calibración

```matlab
calib = calibrate('Source', 'myo', 'UserId', 'daniel', 'Reps', 5, ...
                  'HoldSeconds', 3, 'RelaxSeconds', 2, 'PowerlineHz', 60);
```

La consola muestra cada paso en español e inglés. Pulse **Enter**; el Myo vibra y empieza
una cuenta atrás 3-2-1. Mantenga la contracción hasta que termine el paso.

| # | Paso | Duración | Instrucción |
|---|---|---|---|
| 1 | Reposo | 5 s | Mano completamente relajada |
| 2–6 | Pulgar × 5 | 3 s cada una | Doble solo el pulgar hacia la palma, con fuerza **moderada y constante** |
| 7–11 | Índice × 5 | 3 s cada una | Doble solo el índice |
| 12–16 | Medio × 5 | 3 s cada una | Doble solo el medio |
| 17–21 | Anular × 5 | 3 s cada una | Doble solo el anular (el meñique puede acompañar un poco) |
| 22–26 | Meñique × 5 | 3 s cada una | Doble solo el meñique |
| 27 | MVC de puño | 3 s | Cierre el puño con fuerza **máxima** |
| 28 | MVC de apertura | 3 s | Abra y separe los dedos con fuerza **máxima** |

Consejos:

- Varíe un poco la fuerza entre repeticiones (60–100 %). Así el LDA es más robusto.
- No mueva la muñeca ni el codo.
- Si se equivoca, termine de todas formas y repita toda la calibración.

## 3. Qué se calcula

1. Se descarta el primer 0.5 s de cada contracción.
2. Las ventanas de 200 ms, sin solapamiento, se filtran con la misma cadena que `main`.
3. `rest_rms` / `rest_mav` = mediana de las ventanas de reposo.
4. `mvc_rms` / `mvc_mav` = en cada canal, el **máximo de las medianas de cada tarea**
   (dedos + puño + apertura).
5. Cada ventana se normaliza: `(x − reposo) / (mvc − reposo)`, recortado a [0,1].
6. Rasgos = `[rms_norm, mav_norm]` (16) con las etiquetas `pulgar, D2, D3, D4, D5`.
7. `profiles` = RMS normalizado medio por dedo. `top_channels` = los 2 canales más altos.
8. Se entrena el LDA y se valida con 5 particiones (`cv_accuracy`).
9. Todo se guarda en `config/calibration.mat` (variable `calib`).

La consola imprime la tabla de perfiles:

```
Perfil RMS normalizado
clase      CH1   CH2   CH3   CH4   CH5   CH6   CH7   CH8   | top
pulgar    0.02  0.02  0.05  0.15  0.93  0.65  0.06  0.02   | 5+6
D2        0.02  0.04  0.20  0.79  0.18  0.02  0.42  0.04   | 4+7
...
```

## 4. Cómo juzgar la calidad

| Indicador | Bueno | Aceptable | Repetir |
|---|---|---|---|
| `cv_accuracy` | ≥ 90 % | 80–90 % | < 80 % (el sistema avisa) |
| Canal principal de cada dedo en `profiles` | ≥ 0.6 | 0.4–0.6 | < 0.4 |
| `top_channels` | distintos para cada dedo | dos dedos comparten el 1.er canal | tres o más lo comparten |

Si dos dedos comparten un canal (habitual en anular y meñique), no pasa nada. El LLM y el
LDA usan el patrón completo. Si el brazalete está **rotado**, `top_channels` se desplaza de
forma coherente (por ejemplo D2=5+8 en vez de 4+7). El LLM sigue a `CALIB`.

## 5. Calibración genérica

`setup` crea una calibración sintética (`is_default = true`) para poder probar sin usuario.
`main` avisa cuando está en uso, y el payload envía `CALIB:[…,DEFAULT]`, lo que indica al
LLM que limite su confianza a 0.80. **No la use con un usuario real.**

```matlab
create_calibration_config('Overwrite', true);   % regenerar la calibración genérica
```

## 6. Calibración sin hardware

```matlab
calib = calibrate('Source', 'simulated', 'Interactive', false, 'Seed', 1);
```

Genera los datos al instante con el generador sintético.
