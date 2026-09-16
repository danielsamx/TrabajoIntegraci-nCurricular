// Mano realista: jerarquía mano → dedo → proximal → intermedia → distal.
// Realistic hand: hierarchy hand → finger → proximal → intermediate → distal.
//
// ES: Cada falange cuelga de un grupo "pivote" cuyo origen está EN LA
//     ARTICULACIÓN; la malla de la falange empieza en el pivote y crece hacia
//     +Y. Los extremos de cada falange son esferas centradas en las
//     articulaciones, así que al flexionar la piel no se abre.
//     Las rotaciones son locales. Eje, rango y acoplamiento llegan de
//     /api/spec; aquí solo viven la anatomía (medidas) y el aspecto.
//     Marco de la mano: palma hacia +Z, dedos hacia +Y, pulgar (mano derecha)
//     hacia +X, muñeca hacia −Y.
// EN: Each phalanx hangs from a "pivot" group whose origin sits AT THE JOINT;
//     the phalanx mesh starts at the pivot and grows along +Y. Phalanx ends
//     are spheres centred on the joints, so the skin never opens when flexing.
//     Rotations are local. Axis, range and coupling come from /api/spec; only
//     anatomy (sizes) and looks live here.
//     Hand frame: palm toward +Z, fingers +Y, thumb (right hand) +X, wrist −Y.

import * as THREE from 'three';
import { ellipsoid, meshSDF, roundBox, roundCone, scaled, smax, smin } from './sdf.js';

export const PALETTE = {
  navy: 0x001f3f,
  pink: 0xd81b60,
  amber: 0xffc107,
  white: 0xffffff,
  black: 0x000000,
};

// ---------------------------------------------------------------- anatomía / anatomy (cm)

const FLAT = 0.86; // los dedos son más anchos que gruesos / fingers are wider than thick

// Arco metacarpiano: los nudillos laterales quedan más hacia la palma.
// Metacarpal arch: the outer knuckles sit further toward the palm.
const ARCH = 0.045;
const arch = (x) => ARCH * x * x;

const FINGERS = [
  //  id    MCP (x, y)     giro    radios MCP, PIP, DIP, punta      largos P, I, D
  { id: 'D2', xy: [2.72, 9.45], splay: -0.07, r: [0.95, 0.85, 0.77, 0.69], len: [3.95, 2.35, 1.9] },
  { id: 'D3', xy: [0.88, 9.8], splay: -0.01, r: [0.98, 0.88, 0.79, 0.71], len: [4.35, 2.75, 2.0] },
  { id: 'D4', xy: [-0.94, 9.5], splay: 0.05, r: [0.91, 0.82, 0.74, 0.67], len: [4.05, 2.6, 1.95] },
  { id: 'D5', xy: [-2.62, 8.8], splay: 0.14, r: [0.80, 0.72, 0.65, 0.59], len: [3.2, 1.95, 1.8] },
].map((f) => ({ ...f, mcp: [f.xy[0], f.xy[1], 0.05 + arch(f.xy[0])] }));

export const THUMB = {
  // ES: Ajustado numéricamente para que las yemas se toquen en OK (Y) y PINCH (P).
  // EN: Tuned numerically so the pads meet in OK (Y) and PINCH (P).
  cmc: [3.09, 1.28, 0.65],     // articulación trapeciometacarpiana / CMC joint
  abduction: -0.05,            // giro fijo hacia la palma / fixed palmar tilt (rad, about Y)
  tilt: -0.82,                 // separación del índice / spread from the index (rad, about Z)
  twist: -0.69,                // pronación del pulgar / thumb pronation (rad, about its own axis)
  metacarpal: 3.4,
  r: [1.3, 1.1, 1.0, 0.86],    // CMC, MCP, IP, punta / tip
  len: [2.8, 2.3],             // proximal, distal — sin intermedia / no intermediate
};

const WRIST_Y = -3.4;          // corte de la muñeca / wrist cut
export const GROUND_Y = WRIST_Y;

// ES: Signo por articulación para que el ángulo positivo de la tabla vaya
//     hacia la palma. Para D0, −θ sobre Y lleva el pulgar al frente de la
//     palma (+Z): oposición.
// EN: Per-joint sign so the table's positive angle points toward the palm.
//     For D0, −θ about Y swings the thumb in front of the palm (+Z): opposition.
const SIGN = { D0: -1 };

// ---------------------------------------------------------------- piel / skin

const SKIN_COLOR = new THREE.Color('#efc6b3');
const NAIL_COLOR = new THREE.Color('#f3d8d0');
const RED = [1.0, 0.8, 0.78];

const mix = (a, b, t) => a + (b - a) * t;
const clamp01 = (x) => Math.min(1, Math.max(0, x));
const smooth = (e0, e1, x) => { const t = clamp01((x - e0) / (e1 - e0)); return t * t * (3 - 2 * t); };

function tint(red, ao, pale = 0) {
  const shade = 0.5 + 0.5 * ao;
  return [
    mix(1, RED[0], red) * shade * mix(1, 1.02, pale),
    mix(1, RED[1], red) * shade * mix(1, 1.0, pale),
    mix(1, RED[2], red) * shade * mix(1, 0.96, pale),
  ];
}

// Código GLSL compartido por todos los materiales de piel.
// GLSL shared by every skin material.
const SKIN_GLSL = /* glsl */ `
varying vec3 vObjPos;
varying vec3 vObjN;
varying vec4 vSkin;

float sk_hash(vec3 p) {
  p = fract(p * 0.3183099 + 0.1);
  p *= 17.0;
  return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float sk_noise(vec3 x) {
  vec3 i = floor(x);
  vec3 f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(sk_hash(i + vec3(0, 0, 0)), sk_hash(i + vec3(1, 0, 0)), f.x),
                 mix(sk_hash(i + vec3(0, 1, 0)), sk_hash(i + vec3(1, 1, 0)), f.x), f.y),
             mix(mix(sk_hash(i + vec3(0, 0, 1)), sk_hash(i + vec3(1, 0, 1)), f.x),
                 mix(sk_hash(i + vec3(0, 1, 1)), sk_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float sk_line(float d, float w) { return 1.0 - smoothstep(0.0, w, abs(d)); }
float sk_seg(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a, ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}
float sk_poly(vec2 p, vec2 a, vec2 b, vec2 c, vec2 d) {
  return min(min(sk_seg(p, a, b), sk_seg(p, b, c)), sk_seg(p, c, d));
}

// Pliegues: 0 = nada, 1 = centro del pliegue / Creases: 0 = none, 1 = crease centre
float sk_crease(vec3 p, vec3 n) {
  float kind = vSkin.x;
  float L = vSkin.y;
  float volar = smoothstep(0.15, 0.55, n.z);
  float dorsal = smoothstep(0.2, 0.6, -n.z);
  float wob = (sk_noise(p * 3.1) - 0.5) * 0.06;
  float c = 0.0;
  if (kind < 0.5) {
    // Palma / palm
    vec2 q = p.xy + wob;
    float heart = sk_poly(q, vec2(-3.4, 7.45), vec2(-1.5, 7.85), vec2(0.5, 8.15), vec2(1.9, 8.75));
    float head  = sk_poly(q, vec2(2.9, 7.05), vec2(1.1, 6.35), vec2(-0.9, 5.65), vec2(-2.4, 4.85));
    float life  = sk_poly(q, vec2(2.9, 7.1), vec2(2.05, 5.9), vec2(1.85, 4.2), vec2(2.1, 2.5));
    // los pliegues se afinan hacia los extremos / creases thin out toward their ends
    float fadeH = smoothstep(-3.6, -2.6, q.x) * (1.0 - smoothstep(1.2, 2.1, q.x));
    float fadeD = smoothstep(-2.6, -1.4, q.x);
    float fadeL = smoothstep(2.2, 3.4, q.y);
    float palm = max(max(sk_line(heart, 0.11) * fadeH, sk_line(head, 0.1) * fadeD), sk_line(life, 0.11) * fadeL);
    float wrist = max(sk_line(p.y - 1.05 + wob, 0.08), sk_line(p.y - 0.55 + wob, 0.07)) * (1.0 - smoothstep(1.2, 2.4, abs(p.x)));
    c = max(palm * smoothstep(0.35, 0.7, n.z) * 0.75, wrist * volar * 0.5);
  } else if (kind < 3.5) {
    // Falanges / phalanges: 1 intermedia, 2 distal, 3 proximal
    float base = kind > 2.5 ? 1.35 : (kind > 1.5 ? 0.2 : 0.16);
    float v = sk_line(p.y - base + wob, 0.07);
    if (kind < 1.5 || kind > 2.5) v = max(v, sk_line(p.y - base - 0.2 + wob, 0.055) * 0.7);
    c = v * volar * 0.7 * (1.0 - smoothstep(0.35, 0.95, abs(p.x) / 0.9));
    // arrugas del nudillo / knuckle wrinkles
    float kn = kind > 2.5 ? 0.35 : 1.0;
    float band = (1.0 - smoothstep(0.25, 0.55, abs(p.y - 0.12))) * kn;
    float rings = sk_line(fract((p.y + 0.35 * p.x * p.x + wob) * 7.0) - 0.5, 0.09);
    float breakup = smoothstep(0.35, 0.65, sk_noise(p * vec3(2.5, 9.0, 2.5)));
    c = max(c, rings * band * breakup * dorsal * 0.8);
  } else if (kind < 4.5) {
    // Metacarpo del pulgar: pliegue en su base / thumb metacarpal: crease at its base
    c = sk_line(p.y - 3.45 + wob, 0.08) * volar * 0.45;
  }
  return c;
}

float sk_height(vec3 p, vec3 n) {
  float pores = sk_noise(p * 16.0) * 0.6 + sk_noise(p * 7.0) * 0.4;
  return pores * 0.0035 - sk_crease(p, n) * 0.022;
}

vec3 sk_perturb(vec3 surf_pos, vec3 surf_norm, vec2 dHdxy, float faceDir) {
  vec3 vSigmaX = normalize(dFdx(surf_pos.xyz));
  vec3 vSigmaY = normalize(dFdy(surf_pos.xyz));
  vec3 vN = surf_norm;
  vec3 R1 = cross(vSigmaY, vN);
  vec3 R2 = cross(vN, vSigmaX);
  float fDet = dot(vSigmaX, R1) * faceDir;
  vec3 vGrad = sign(fDet) * (dHdxy.x * R1 + dHdxy.y * R2);
  return normalize(abs(fDet) * surf_norm - vGrad);
}
`;

function makeSkinMaterial() {
  const m = new THREE.MeshPhysicalMaterial({
    color: SKIN_COLOR,
    vertexColors: true,
    roughness: 0.58,
    metalness: 0,
    sheen: 0.55,
    sheenRoughness: 0.75,
    sheenColor: new THREE.Color('#ffb3a3'),
    clearcoat: 0.08,
    clearcoatRoughness: 0.55,
    specularIntensity: 0.45,
  });
  m.onBeforeCompile = (shader) => {
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', `#include <common>
attribute vec4 aSkin;
varying vec3 vObjPos;
varying vec3 vObjN;
varying vec4 vSkin;`)
      .replace('#include <begin_vertex>', `#include <begin_vertex>
vObjPos = position; vObjN = normal; vSkin = aSkin;`);
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', `#include <common>\n${SKIN_GLSL}`)
      .replace('#include <color_fragment>', `#include <color_fragment>
{
  vec3 on = normalize(vObjN);
  float cr = sk_crease(vObjPos, on);
  float mottled = sk_noise(vObjPos * 2.2) * 0.6 + sk_noise(vObjPos * 5.5) * 0.4;
  diffuseColor.rgb *= mix(vec3(1.0), vec3(0.93, 0.95, 0.97), mottled * 0.55);
  diffuseColor.rgb *= mix(vec3(1.0), vec3(0.86, 0.74, 0.72), cr);
}`)
      .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
{
  float hh = sk_height(vObjPos, normalize(vObjN));
  normal = sk_perturb(-vViewPosition, normal, vec2(dFdx(hh), dFdy(hh)) * 1.0, faceDirection);
}`)
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
{
  // luz que atraviesa la piel en los bordes / light bleeding through the skin at the rim
  float rim = 1.0 - clamp(dot(normalize(vNormal), normalize(vViewPosition)), 0.0, 1.0);
  totalEmissiveRadiance += vec3(0.30, 0.07, 0.04) * pow(rim, 2.5) * 0.35;
}`);
  };
  m.customProgramCacheKey = () => 'prosthesis-skin-v1';
  return m;
}

function makeNailMaterial() {
  return new THREE.MeshPhysicalMaterial({
    color: NAIL_COLOR,
    vertexColors: true,
    roughness: 0.35,
    clearcoat: 0.35,
    clearcoatRoughness: 0.3,
    sheen: 0.2,
    sheenColor: new THREE.Color('#ffd7cf'),
    side: THREE.DoubleSide,
  });
}

function withKind(geo, kind, length) {
  const n = geo.getAttribute('position').count;
  const a = new Float32Array(n * 4);
  for (let i = 0; i < n; i++) { a[i * 4] = kind; a[i * 4 + 1] = length; }
  geo.setAttribute('aSkin', new THREE.BufferAttribute(a, 4));
  return geo;
}

// ---------------------------------------------------------------- piezas / pieces

/** Falange en su marco local / Phalanx in its local frame. */
function phalanxGeometry(L, ra, rb, role, cell) {
  const core = scaled(roundCone([0, 0, 0], [0, L, 0], ra, rb), [1, 1, FLAT]);
  const distal = role === 'distal';
  const pad = distal
    ? ellipsoid([0, L * 0.6, rb * 0.24], [rb * 0.9, L * 0.44, rb * 0.74])
    : ellipsoid([0, L * 0.52, rb * 0.26], [rb * 0.86, L * 0.36, rb * 0.72]);
  let knuckle = null;
  if (role === 'proximal') knuckle = ellipsoid([0, 0.1, -ra * 0.4], [ra * 0.58, ra * 0.55, ra * 0.52]);
  // yema: la punta cae ligeramente hacia la palma / pulp: the tip dips toward the palm
  const tipPulp = distal ? ellipsoid([0, L * 0.92, rb * 0.18], [rb * 0.8, rb * 0.72, rb * 0.72]) : null;
  const sdf = (x, y, z) => {
    let d = smin(core(x, y, z), pad(x, y, z), 0.25);
    if (knuckle) d = smin(d, knuckle(x, y, z), 0.2);
    if (tipPulp) d = smin(d, tipPulp(x, y, z), 0.25);
    return d;
  };
  const m = ra + 0.35;
  const box = { min: [-m, -ra - 0.3, -m], max: [m, L + rb + 0.3, m] };
  const kind = role === 'proximal' ? 3 : distal ? 2 : 1;
  const geo = meshSDF(sdf, box, cell, (p, n, ao) => {
    const t = p.y / L;
    let red = 0.1;
    if (distal) red += 0.35 * smooth(0.5, 1.1, t);
    if (n.z < 0) red += 0.3 * (1 - smooth(0.0, 0.6, Math.abs(p.y))) * smooth(0.1, 0.6, -n.z);
    if (n.z > 0) red += 0.12 * smooth(0.2, 0.8, n.z);
    return tint(clamp01(red), ao);
  });
  return withKind(geo, kind, L);
}

/** Uña sobre la cara dorsal (−Z) de la falange distal / Nail on the distal phalanx's dorsal (−Z) side. */
function nailGeometry(L, ra, rb) {
  const U = 18, V = 16;
  const y0 = L * 0.4, y1 = L + rb * 0.5;
  const pos = [], col = [], index = [];
  for (let j = 0; j <= V; j++) {
    const t = j / V;
    const y = y0 + (y1 - y0) * t;
    const R = y <= L ? ra + (rb - ra) * (y / L) : Math.sqrt(Math.max(rb * rb - (y - L) ** 2, 1e-4));
    const baseRound = t < 0.28 ? 0.5 + 0.5 * Math.sqrt(1 - ((0.28 - t) / 0.28) ** 2) : 1;
    const half = 0.98 * baseRound * (t > 0.85 ? mix(1, 0.93, (t - 0.85) / 0.15) : 1);
    for (let i = 0; i <= U; i++) {
      const u = (i / U) * 2 - 1;
      const th = u * half;
      let lift = 0.028 - 0.07 * u ** 6;
      if (t < 0.1) lift -= 0.06 * (1 - t / 0.1);
      const rr = R + lift;
      pos.push(Math.sin(th) * rr, y, -Math.cos(th) * rr * FLAT - 0.012);
      // lúnula clara, cuerpo rosado, borde libre blanco / pale lunula, pink body, white free edge
      const lunula = (1 - smooth(0.08, 0.22, t)) * (1 - Math.abs(u) * 0.6);
      const free = smooth(0.86, 0.94, t);
      const r = mix(mix(0.98, 1.0, lunula), 1.0, free);
      const g = mix(mix(0.86, 0.94, lunula), 0.97, free);
      const b = mix(mix(0.84, 0.92, lunula), 0.93, free);
      col.push(r, g, b);
    }
  }
  for (let j = 0; j < V; j++) {
    for (let i = 0; i < U; i++) {
      const a = j * (U + 1) + i, b = a + 1, c = a + U + 1, d = c + 1;
      index.push(a, c, b, b, c, d);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  geo.setIndex(index);
  geo.computeVertexNormals();
  return geo;
}

/** Metacarpo del pulgar con la eminencia tenar / Thumb metacarpal with the thenar eminence. */
function thumbMetacarpalGeometry(cell) {
  const L = THUMB.metacarpal;
  const [r0, r1] = THUMB.r;
  const core = scaled(roundCone([0, 0, 0], [0, L, 0], r0, r1), [1, 1, 0.92]);
  const thenar = ellipsoid([-0.45, 1.5, 0.4], [1.15, 2.0, 0.95]);
  const knuckle = ellipsoid([0, L - 0.05, -r1 * 0.35], [r1 * 0.8, r1 * 0.7, r1 * 0.7]);
  const sdf = (x, y, z) => smin(smin(core(x, y, z), thenar(x, y, z), 0.9), knuckle(x, y, z), 0.3);
  const box = { min: [-2.6, -1.6, -1.8], max: [1.8, L + 1.4, 2.1] };
  const geo = meshSDF(sdf, box, cell, (p, n, ao) => tint(0.12 + 0.12 * smooth(0.2, 0.9, n.z), ao));
  return withKind(geo, 4, L);
}

/** Palma y muñeca, en el marco de la mano / Palm and wrist, in the hand frame. */
function palmGeometry(cell) {
  const parts = [];
  for (const f of FINGERS) {
    const [x, y, z] = f.mcp;
    parts.push(roundCone([x * 0.5, 2.6, 0.1 + arch(x * 0.5)], [x, y - 0.1, z], 0.9, f.r[0] * 0.97));
  }
  const coreBox = roundBox([-0.05, 5.6, 0.3], [3.4, 3.05, 1.0], 0.98);
  const core = (x, y, z) => coreBox(x, y, z - arch(x));   // arco transversal / transverse arch
  const pads = ellipsoid([0.0, 9.05, 0.8], [3.05, 1.3, 0.85]);
  const webs = ellipsoid([0.0, 9.55, 0.45], [2.9, 0.7, 0.6]);
  const hypothenar = ellipsoid([-2.5, 4.8, 0.65], [1.05, 2.9, 0.95]);
  const thenarBase = ellipsoid([2.9, 3.4, 1.0], [1.95, 2.7, 1.2]);
  const web = scaled(roundCone([2.8, 8.2, 0.45], [4.85, 4.75, 0.8], 0.5, 0.78), [1, 1, 0.6], [0, 0, 0.62]);
  const wrist = scaled(roundCone([0.1, 2.8, 0.15], [0.1, WRIST_Y - 1.0, 0.15], 1.6, 1.5), [1.55, 1, 1], [0.1, 0, 0.15]);
  const sdf = (x, y, z) => {
    let d = core(x, y, z);
    for (const p of parts) d = smin(d, p(x, y, z), 0.9);
    d = smin(d, pads(x, y, z), 0.8);
    d = smin(d, webs(x, y, z), 0.5);
    d = smin(d, hypothenar(x, y, z), 0.9);
    d = smin(d, thenarBase(x, y, z), 1.0);
    d = smin(d, web(x, y, z), 0.8);
    d = smin(d, wrist(x, y, z), 1.8);
    return smax(d, WRIST_Y - y, 0.35);
  };
  const box = { min: [-5.0, WRIST_Y - 0.4, -2.4], max: [6.6, 11.4, 3.2] };
  const geo = meshSDF(sdf, box, cell, (p, n, ao) => {
    let red = 0.08;
    red += 0.22 * smooth(0.3, 0.9, n.z) * smooth(2.0, 5.0, p.y);                 // palma / palm
    red += 0.2 * smooth(7.6, 9.4, p.y) * smooth(0.2, 0.7, -n.z);                 // nudillos / knuckles
    const pale = 1 - smooth(0.5, 3.0, p.y);                                       // muñeca / wrist
    return tint(clamp01(red * (1 - 0.6 * pale)), ao, pale);
  });
  return withKind(geo, 0, 0);
}

// ---------------------------------------------------------------- construcción / build

function pivot(id, y) {
  const g = new THREE.Group();
  g.name = id;
  g.position.y = y;
  return g;
}

/**
 * @param {object} spec  respuesta de /api/spec
 * @param {{mirror?: boolean, geometry?: boolean, quality?: number}} [opts]
 *   geometry=false construye solo la cadena cinemática (pruebas).
 *   geometry=false builds only the kinematic chain (tests).
 */
export function buildHand(spec, { mirror = false, geometry = true, quality = 1 } = {}) {
  const jointsById = Object.fromEntries(spec.joints.map((j) => [j.id, j]));
  const pivots = {};
  const tips = {};
  const letters = spec.actuators.map((a) => a.letter);

  const skin = Object.fromEntries(letters.map((k) => [k, geometry ? makeSkinMaterial() : null]));
  const nails = Object.fromEntries(letters.map((k) => [k, geometry ? makeNailMaterial() : null]));
  const palmMaterial = geometry ? makeSkinMaterial() : null;

  const segCell = 0.07 / quality;
  const palmCell = 0.12 / quality;

  const root = new THREE.Group();
  root.name = 'hand';
  // ES: La mano izquierda es la misma geometría con X invertida.
  // EN: The left hand is the same geometry with X mirrored.
  if (mirror) root.scale.x = -1;

  const add = (parent, geo, material) => {
    const mesh = new THREE.Mesh(geo, material);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    parent.add(mesh);
    return mesh;
  };

  if (geometry) add(root, palmGeometry(palmCell), palmMaterial).name = 'palm';

  const chain = (parent, prefix, segs, lengths, radii, startY, motor) => {
    let p = parent;
    segs.forEach((seg, i) => {
      const id = `${prefix}_${seg}`;
      if (!jointsById[id]) throw new Error(`Joint ${id} missing from /api/spec`);
      const pv = pivot(id, i === 0 ? startY : lengths[i - 1]);
      p.add(pv);
      pivots[id] = pv;
      const role = i === segs.length - 1 ? 'distal' : (i === 0 && prefix !== 'D1' ? 'proximal' : 'middle');
      if (geometry) {
        add(pv, phalanxGeometry(lengths[i], radii[i], radii[i + 1], role, segCell), skin[jointsById[id].motor]);
        if (role === 'distal') add(pv, nailGeometry(lengths[i], radii[i], radii[i + 1]), nails[motor]).castShadow = false;
      }
      p = pv;
    });
    const tip = new THREE.Object3D();
    tip.position.set(0, lengths[lengths.length - 1] + radii[radii.length - 1] * 0.2, radii[radii.length - 1] * 0.35);
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
    const motor = jointsById[`${f.id}_P`].motor;
    chain(finger, f.id, ['P', 'I', 'D'], f.len, f.r, 0, motor);
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
  if (geometry) add(mount, thumbMetacarpalGeometry(segCell * 1.3), skin[jointsById.D0.motor]);
  chain(mount, 'D1', ['P', 'D'], THUMB.len, THUMB.r.slice(1), THUMB.metacarpal, jointsById.D1_P.motor);

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
    if (!geometry) return false;
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
      skin[k].color.copy(SKIN_COLOR).lerp(hue[k], level[k]);
      nails[k].color.copy(NAIL_COLOR).lerp(hue[k], level[k] * 0.6);
    }
    return changing;
  }

  function setHighlight(on) { highlight = on; }


  return { root, apply, paint, setHighlight, pivots, tips };
}
