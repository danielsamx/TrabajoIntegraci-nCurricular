// Esqueleto articulado de la mano: jerarquía mano → dedo → proximal → intermedia → distal.
// Hand skeleton: hierarchy hand → finger → proximal → intermediate → distal.
//
// ES: Aquí vive la cinemática y nada más. Cada falange cuelga de un grupo
//     "pivote" cuyo origen está EN LA ARTICULACIÓN, y las rotaciones son
//     locales: cada ángulo es relativo a la falange padre. El eje, el rango y
//     el acoplamiento llegan de /api/spec; las medidas, de anatomy.js; el
//     aspecto de cada pieza, del estilo elegido (style-human.js o
//     style-robot.js). Cambiar de estilo no cambia una sola rotación.
// EN: Kinematics live here and nothing else. Each phalanx hangs from a "pivot"
//     group whose origin sits AT THE JOINT, and rotations are local: each
//     angle is relative to its parent phalanx. Axis, range and coupling come
//     from /api/spec; sizes from anatomy.js; the looks of each part from the
//     chosen style (style-human.js or style-robot.js). Switching styles does
//     not change a single rotation.

import * as THREE from 'three';
import { FINGERS, PALETTE, SIGN, THUMB } from './anatomy.js';
import { createHumanStyle } from './style-human.js';
import { createRobotStyle } from './style-robot.js';

export { GROUND_Y, PALETTE } from './anatomy.js';

/** Estilos disponibles / Available styles. */
export const STYLES = {
  human: createHumanStyle,
  robot: createRobotStyle,
};

export const DEFAULT_STYLE = 'human';

function pivot(id, y) {
  const g = new THREE.Group();
  g.name = id;
  g.position.y = y;
  return g;
}

/**
 * @param {object} spec  respuesta de /api/spec / the /api/spec response
 * @param {{style?: 'human'|'robot', mirror?: boolean, geometry?: boolean, quality?: number}} [opts]
 *   geometry=false construye solo la cadena cinemática (pruebas).
 *   geometry=false builds only the kinematic chain (tests).
 */
export function buildHand(spec, { style = DEFAULT_STYLE, mirror = false, geometry = true, quality = 1 } = {}) {
  const jointsById = Object.fromEntries(spec.joints.map((j) => [j.id, j]));
  const pivots = {};
  const tips = {};
  const letters = spec.actuators.map((a) => a.letter);
  if (!STYLES[style]) throw new Error(`Unknown hand style: ${style}`);
  const maker = geometry ? STYLES[style]({ letters, quality }) : null;

  const root = new THREE.Group();
  root.name = `hand:${style}`;
  // ES: La mano izquierda es la misma geometría con X invertida.
  // EN: The left hand is the same geometry with X mirrored.
  if (mirror) root.scale.x = -1;

  if (maker) {
    const palm = maker.palm();
    if (palm) {
      palm.name = 'palm';
      root.add(palm);
    }
  }

  const chain = (parent, prefix, segs, lengths, radii, startY) => {
    let p = parent;
    segs.forEach((seg, i) => {
      const id = `${prefix}_${seg}`;
      if (!jointsById[id]) throw new Error(`Joint ${id} missing from /api/spec`);
      const pv = pivot(id, i === 0 ? startY : lengths[i - 1]);
      p.add(pv);
      pivots[id] = pv;
      const role = i === segs.length - 1 ? 'distal' : (i === 0 && prefix !== 'D1' ? 'proximal' : 'middle');
      if (maker) {
        pv.add(maker.phalanx({
          finger: prefix, seg, role,
          L: lengths[i], ra: radii[i], rb: radii[i + 1],
          motor: jointsById[id].motor,
        }));
      }
      p = pv;
    });
    // Punto de contacto de la yema, para comprobar las pinzas.
    // Pad contact point, used to check the pinches.
    const tip = new THREE.Object3D();
    const last = lengths.length - 1;
    tip.position.set(0, lengths[last] + radii[radii.length - 1] * 0.2, radii[radii.length - 1] * 0.35);
    p.add(tip);
    tips[prefix] = tip;
  };

  // Dedos largos / Long fingers
  for (const f of FINGERS) {
    const finger = new THREE.Group();
    finger.name = f.id;
    finger.position.fromArray(f.mcp);
    finger.rotation.z = f.splay;
    root.add(finger);
    chain(finger, f.id, ['P', 'I', 'D'], f.len, f.r, 0);
  }

  // Pulgar / Thumb: CMC → D0 (Y, oposición) → orientación fija → metacarpo → D1_P → D1_D
  const thumb = new THREE.Group();
  thumb.name = 'D1';
  thumb.position.fromArray(THUMB.cmc);
  thumb.rotation.y = THUMB.abduction;
  root.add(thumb);

  const d0 = pivot('D0', 0);
  thumb.add(d0);
  pivots.D0 = d0;

  const mount = new THREE.Group();
  mount.rotation.set(0, THUMB.twist, THUMB.tilt, 'ZYX');
  d0.add(mount);
  if (maker) {
    const metacarpal = maker.thumbMetacarpal({ L: THUMB.metacarpal, motor: jointsById.D0.motor });
    if (metacarpal) mount.add(metacarpal);
  }
  chain(mount, 'D1', ['P', 'D'], THUMB.len, THUMB.r.slice(1), THUMB.metacarpal);

  const unknown = spec.joints.filter((j) => !pivots[j.id]).map((j) => j.id);
  if (unknown.length) throw new Error(`No geometry for joints: ${unknown.join(', ')}`);

  /** Aplica posiciones normalizadas por actuador / Apply normalised positions per actuator. */
  function apply(normalised) {
    for (const j of spec.joints) {
      const n = normalised[j.motor] ?? 0;
      const t = Math.min(1, Math.max(0, n * j.coupling));
      const deg = j.min_deg + t * (j.max_deg - j.min_deg);
      const rad = THREE.MathUtils.degToRad(deg) * (SIGN[j.id] ?? 1);
      const p = pivots[j.id];
      p.rotation.set(0, 0, 0);
      if (j.axis === 'X') p.rotation.x = rad;
      else if (j.axis === 'Y') p.rotation.y = rad;
      else p.rotation.z = rad;
    }
  }

  // Tinte suave por actuador / Soft per-actuator tint.
  const PINK = new THREE.Color(PALETTE.pink);
  const AMBER = new THREE.Color(PALETTE.amber);
  const level = Object.fromEntries(letters.map((k) => [k, 0]));
  const hue = Object.fromEntries(letters.map((k) => [k, PINK]));
  let highlight = true;

  /** Estado visual por actuador: 'idle' | 'moving' | 'warn'. Llamar en cada fotograma.
   *  Devuelve true mientras el tinte cambia / Returns true while the tint is changing. */
  function paint(stateByActuator, dt = 1 / 60) {
    if (!maker) return false;
    let changing = false;
    for (const k of letters) {
      const s = highlight ? stateByActuator[k] : 'idle';
      const target = s === 'moving' ? 0.3 : s === 'warn' ? 0.38 : 0;
      if (s === 'moving') hue[k] = PINK;
      else if (s === 'warn') hue[k] = AMBER;
      if (Math.abs(target - level[k]) < 0.002) {
        if (level[k] === target) continue;
        level[k] = target;
      } else {
        level[k] += (target - level[k]) * Math.min(1, dt * 10);
      }
      changing = true;
      maker.tint(k, hue[k], level[k]);
    }
    return changing;
  }

  function setHighlight(on) {
    highlight = on;
  }

  return { root, style, apply, paint, setHighlight, pivots, tips };
}
