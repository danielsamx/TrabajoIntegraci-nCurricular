// Interpolación en el espacio normalizado de cada actuador.
// Interpolation in each actuator's normalised space.
//
// ES: El servidor manda el destino y la duración UNA vez; aquí se interpola con
//     requestAnimationFrame. Un comando nuevo reorienta desde la pose actual:
//     no hay cola. La curva es la misma que app/motion.py.
// EN: The server sends the target and duration ONCE; interpolation happens here
//     with requestAnimationFrame. A new command re-targets from the current
//     pose: there is no queue. The curve matches app/motion.py.

export function easeInOutCubic(u) {
  u = Math.min(1, Math.max(0, u));
  return u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2;
}

export class ActuatorAnimator {
  constructor(letters) {
    this.tracks = {};
    for (const k of letters) this.tracks[k] = still(0, 0, 0);
  }

  valueAt(k, now) {
    const t = this.tracks[k];
    const u = t.dur > 0 ? (now - t.start) / t.dur : 1;
    const e = easeInOutCubic(u);
    return {
      n: t.fromN + (t.toN - t.fromN) * e,
      c: t.fromC + (t.toC - t.fromC) * e,
      toC: t.toC,
    };
  }

  isMoving(k, now) {
    const t = this.tracks[k];
    return t.dur > 0 && now - t.start < t.dur && (t.fromN !== t.toN || t.fromC !== t.toC);
  }

  /** Reorienta desde donde esté / Re-target from wherever it is. */
  retarget(k, toN, toC, durMs, now) {
    const cur = this.valueAt(k, now);
    this.tracks[k] = { fromN: cur.n, toN, fromC: cur.c, toC, start: now, dur: durMs };
  }

  /** Congela en un valor, sin animar / Freeze at a value, without animating. */
  freeze(k, n, c, now) {
    this.tracks[k] = still(n, c, now);
  }

  /** Cambia las cuentas mostradas sin mover la mano (calibración).
   *  Change displayed counts without moving the hand (calibration). */
  setCounts(k, c, now) {
    const cur = this.valueAt(k, now);
    this.tracks[k] = still(cur.n, c, now);
  }

  /** Continúa una trayectoria ya empezada (snapshot al conectar).
   *  Resume a trajectory that already started (snapshot on connect). */
  resume(k, tr, now) {
    this.tracks[k] = {
      fromN: tr.from, toN: tr.to, fromC: tr.from_counts, toC: tr.to_counts,
      start: now - tr.elapsed_ms, dur: tr.duration_ms,
    };
  }
}

function still(n, c, now) {
  return { fromN: n, toN: n, fromC: c, toC: c, start: now, dur: 0 };
}
