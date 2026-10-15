// Estilo robótico: carcasas, ejes y almohadillas de agarre.
// Robotic style: shells, axles and grip pads.
//
// ES: Misma anatomía y mismos pivotes que el estilo humano (hand.js no sabe de
//     estilos): lo que cambia es la forma de cada pieza. Cada falange es una
//     carcasa cónica con un bloque de articulación en su origen, un eje negro
//     que sobresale y una barra de empuje dorsal. La palma es un chasis con
//     tapa atornillada, los soportes de los nudillos y el eje del pulgar.
// EN: Same anatomy and same pivots as the human style (hand.js knows nothing
//     about styles): only the shape of each part changes. Each phalanx is a
//     tapered shell with a joint block at its origin, a protruding black axle
//     and a dorsal push rod. The palm is a chassis with a bolted cover, the
//     knuckle mounts and the thumb's rotation axis.

import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { FINGERS, PALETTE, THUMB, WRIST_Y } from './anatomy.js';

const SHELL_COLOR = new THREE.Color(PALETTE.white);
const FRAME_COLOR = new THREE.Color(PALETTE.navy);

const GAP = 0.22;          // holgura en la articulación / clearance at the joint
const WIDTH = 1.72;        // ancho de la carcasa respecto al radio / shell width vs radius
const DEPTH = 1.42;        // grosor de la carcasa respecto al radio / shell depth vs radius

function shellMaterial() {
  // Carcasa de plástico técnico / engineering-plastic shell.
  return new THREE.MeshPhysicalMaterial({
    color: SHELL_COLOR, roughness: 0.38, metalness: 0.0,
    clearcoat: 0.55, clearcoatRoughness: 0.28,
  });
}

function frameMaterial() {
  // Estructura de aluminio anodizado / anodised aluminium frame.
  return new THREE.MeshPhysicalMaterial({
    color: FRAME_COLOR, roughness: 0.34, metalness: 0.65,
  });
}

/**
 * Caja redondeada afilada hacia la punta.
 * Rounded box tapered toward the tip.
 */
function taperedBox(w, h, d, radius, taper, segments = 3) {
  const geo = new RoundedBoxGeometry(w, h, d, segments, radius);
  const pos = geo.getAttribute('position');
  for (let i = 0; i < pos.count; i++) {
    const y = pos.getY(i);
    const t = (y + h / 2) / h;                       // 0 en la base, 1 en la punta
    const k = 1 + (taper - 1) * t;
    pos.setX(i, pos.getX(i) * k);
    pos.setZ(i, pos.getZ(i) * k);
  }
  geo.computeVertexNormals();
  return geo;
}

/** Cilindro con su eje en X / Cylinder with its axis along X. */
function axleGeometry(radius, length, segments = 20) {
  const geo = new THREE.CylinderGeometry(radius, radius, length, segments);
  geo.rotateZ(Math.PI / 2);
  return geo;
}

export function createRobotStyle({ letters }) {
  const shell = Object.fromEntries(letters.map((k) => [k, shellMaterial()]));
  const frame = Object.fromEntries(letters.map((k) => [k, frameMaterial()]));
  const palmShell = shellMaterial();
  const palmFrame = frameMaterial();
  // Piezas que no se tiñen / parts that are never tinted.
  const steel = new THREE.MeshPhysicalMaterial({ color: 0x11161c, roughness: 0.3, metalness: 0.9 });
  const rubber = new THREE.MeshPhysicalMaterial({ color: PALETTE.black, roughness: 0.95, metalness: 0 });

  const mesh = (geo, material, parent) => {
    const m = new THREE.Mesh(geo, material);
    m.castShadow = true;
    m.receiveShadow = true;
    if (parent) parent.add(m);
    return m;
  };

  /** Eje de articulación: bloque + pasador que asoma a los lados.
   *  Joint axis: block plus a pin protruding on both sides. */
  function joint(parent, radius, width, material, y = 0) {
    const g = new THREE.Group();
    g.position.y = y;
    parent.add(g);
    const block = mesh(new THREE.CylinderGeometry(radius, radius, width * 0.86, 24), material, g);
    block.rotation.z = Math.PI / 2;
    mesh(axleGeometry(radius * 0.42, width * 1.1), steel, g);
    return g;
  }

  function phalanx({ role, L, ra, rb, motor }) {
    const group = new THREE.Group();
    const w = ra * WIDTH;
    const d = ra * DEPTH;
    const taper = Math.max(0.55, rb / ra);
    const bodyLen = Math.max(0.3, L - GAP);

    // Carcasa / shell
    const body = mesh(taperedBox(w, bodyLen, d, Math.min(w, d) * 0.28, taper), shell[motor], group);
    body.position.y = GAP / 2 + bodyLen / 2;

    // Articulación en el origen del pivote / joint at the pivot origin
    joint(group, ra * 0.6, w * 0.98, frame[motor]);

    // Barra de empuje dorsal / dorsal push rod
    const rod = mesh(
      new THREE.BoxGeometry(w * 0.24, bodyLen * 0.66, d * 0.13),
      frame[motor], group,
    );
    rod.position.set(0, GAP / 2 + bodyLen * 0.5, -d * 0.45 * (1 + taper) / 2);

    if (role === 'distal') {
      // Punta redondeada y almohadilla de agarre / rounded tip and grip pad
      const tip = mesh(new THREE.SphereGeometry(rb * 0.82, 20, 14), shell[motor], group);
      tip.position.y = L - rb * 0.12;
      tip.scale.set(1, 0.95, 0.88);
      const pad = mesh(
        new RoundedBoxGeometry(w * 0.74 * taper, bodyLen * 0.72, 0.3, 2, 0.12),
        rubber, group,
      );
      pad.position.set(0, GAP / 2 + bodyLen * 0.58, d * 0.48 * taper);
      pad.rotation.x = -0.12;
    } else {
      // Placas laterales del varillaje / linkage side plates
      for (const sx of [-1, 1]) {
        const plate = mesh(new THREE.BoxGeometry(0.12, bodyLen * 0.5, d * 0.5), frame[motor], group);
        plate.position.set(sx * w * 0.5, GAP / 2 + bodyLen * 0.3, -d * 0.1);
      }
    }
    return group;
  }

  function thumbMetacarpal({ L, motor }) {
    const group = new THREE.Group();
    const [r0, r1] = THUMB.r;
    const w = r0 * WIDTH * 0.95;
    const d = r0 * DEPTH;
    const bodyLen = L - GAP;

    // Rotor de oposición: gira sobre el eje Y del pulgar / opposition rotor: turns about the thumb's Y axis
    const rotor = mesh(new THREE.CylinderGeometry(r0 * 0.92, r0 * 0.98, 1.2, 28), frame[motor], group);
    rotor.position.y = 0.25;

    const body = mesh(taperedBox(w, bodyLen, d, Math.min(w, d) * 0.3, r1 / r0), shell[motor], group);
    body.position.y = GAP / 2 + bodyLen / 2 + 0.5;

    // Articulación metacarpofalángica, en el extremo / metacarpophalangeal joint, at the far end
    joint(group, r1 * 0.62, w * 0.95, frame[motor], L);
    return group;
  }

  function palm() {
    const group = new THREE.Group();
    const top = 9.3, bottom = 1.6, height = top - bottom;
    // ES: El chasis se estrecha hacia la muñeca y deja libre el lado del pulgar.
    // EN: The chassis narrows toward the wrist and leaves the thumb side clear.
    const cx = -0.55;

    const chassis = mesh(taperedBox(5.9, height, 2.3, 0.45, 1.14), palmShell, group);
    chassis.position.set(cx, (top + bottom) / 2, 0.25);

    // Tapa dorsal atornillada / bolted dorsal cover
    const cover = mesh(new RoundedBoxGeometry(4.6, height * 0.72, 0.4, 2, 0.16), palmFrame, group);
    cover.position.set(cx, (top + bottom) / 2 - 0.2, -1.12);
    for (const [sx, sy] of [[-1, -1], [-1, 1], [1, -1], [1, 1]]) {
      const bolt = mesh(new THREE.CylinderGeometry(0.15, 0.15, 0.2, 12), steel, group);
      bolt.rotation.x = Math.PI / 2;
      bolt.position.set(cx + sx * 1.9, (top + bottom) / 2 - 0.2 + sy * height * 0.29, -1.32);
    }
    // Rejillas de ventilación / vents
    for (let i = -1; i <= 1; i++) {
      const vent = mesh(new THREE.BoxGeometry(0.26, height * 0.4, 0.12), steel, group);
      vent.position.set(cx + i * 0.8, (top + bottom) / 2 + 0.5, -1.32);
    }

    // Placa palmar con almohadillas de agarre / palm plate with grip pads
    const plate = mesh(new RoundedBoxGeometry(4.3, height * 0.62, 0.35, 2, 0.14), palmFrame, group);
    plate.position.set(cx, (top + bottom) / 2 - 0.1, 1.35);
    for (const [px, py] of [[-1.1, 1.4], [1.1, 1.4], [0, -1.3]]) {
      const pad = mesh(new RoundedBoxGeometry(1.5, 1.2, 0.26, 2, 0.1), rubber, group);
      pad.position.set(cx + px, (top + bottom) / 2 - 0.1 + py, 1.5);
    }

    // Soportes de los nudillos: cuello + eje / knuckle mounts: neck + axis
    for (const f of FINGERS) {
      const [x, y, z] = f.mcp;
      const neck = mesh(taperedBox(f.r[0] * 1.58, y - 7.4, 2.0, 0.3, 0.92), palmShell, group);
      neck.position.set(x * 0.92, (y + 7.4) / 2 - 0.1, z * 0.7 + 0.1);
      const mount = mesh(new THREE.CylinderGeometry(f.r[0] * 0.8, f.r[0] * 0.8, f.r[0] * 1.9, 24), palmFrame, group);
      mount.rotation.z = Math.PI / 2;
      mount.position.set(x, y, z);
    }

    // Módulo del pulgar: soporte y eje de oposición (vertical, en la CMC).
    // Thumb module: bracket and opposition axis (vertical, at the CMC).
    const [tx, ty, tz] = THUMB.cmc;
    const bracket = mesh(taperedBox(2.3, 4.6, 2.4, 0.4, 0.8), palmShell, group);
    bracket.position.set(tx - 0.5, ty + 1.1, tz - 0.1);
    bracket.rotation.z = -0.18;
    const post = mesh(new THREE.CylinderGeometry(0.5, 0.5, 3.0, 24), steel, group);
    post.position.set(tx, ty + 0.5, tz);
    // Servo de oposición (MG90S), fijo en la palma / opposition servo (MG90S), fixed in the palm
    const servo = mesh(new RoundedBoxGeometry(2.2, 1.25, 2.3, 2, 0.12), palmFrame, group);
    servo.position.set(tx - 1.15, ty - 0.55, tz - 0.05);

    // Muñeca: acople y brida / wrist: coupling and flange
    const wrist = mesh(new THREE.CylinderGeometry(1.5, 1.62, bottom - WRIST_Y + 0.7, 32), palmShell, group);
    wrist.position.set(cx * 0.4, (bottom + WRIST_Y) / 2, 0.2);
    const collar = mesh(new THREE.CylinderGeometry(1.78, 1.78, 0.5, 32), steel, group);
    collar.position.set(cx * 0.4, WRIST_Y + 0.25, 0.2);
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * Math.PI * 2;
      const bolt = mesh(new THREE.CylinderGeometry(0.13, 0.13, 0.56, 10), palmFrame, group);
      bolt.position.set(cx * 0.4 + Math.cos(a) * 1.38, WRIST_Y + 0.25, 0.2 + Math.sin(a) * 1.38);
    }
    return group;
  }

  return {
    id: 'robot',
    palm,
    phalanx,
    thumbMetacarpal,
    tint(letter, color, amount) {
      shell[letter].color.copy(SHELL_COLOR).lerp(color, amount);
      frame[letter].color.copy(FRAME_COLOR).lerp(color, amount * 0.8);
    },
  };
}
