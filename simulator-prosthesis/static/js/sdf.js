// Campos de distancia con signo (SDF) y mallado por "surface nets".
// Signed distance fields (SDF) and "surface nets" meshing.
//
// ES: La piel de la mano se describe como una unión suave de formas simples
//     (conos redondeados, elipsoides) y se convierte en malla una sola vez al
//     cargar la página. Así la palma, los nudillos y las yemas quedan
//     orgánicos sin depender de un modelo externo.
// EN: The hand's skin is described as a smooth union of simple shapes (round
//     cones, ellipsoids) and meshed once on page load. That keeps the palm,
//     knuckles and pads organic without an external model file.

import * as THREE from 'three';

// ---------------------------------------------------------------- primitivas / primitives

export function smin(a, b, k) {
  if (k <= 0) return Math.min(a, b);
  const h = Math.max(k - Math.abs(a - b), 0) / k;
  return Math.min(a, b) - h * h * k * 0.25;
}

export function smax(a, b, k) {
  return -smin(-a, -b, k);
}

/** Cono redondeado de a (radio r1) a b (radio r2). Inigo Quilez. */
export function roundCone(a, b, r1, r2) {
  const bax = b[0] - a[0], bay = b[1] - a[1], baz = b[2] - a[2];
  const l2 = bax * bax + bay * bay + baz * baz;
  const rr = r1 - r2;
  const a2 = l2 - rr * rr;
  const il2 = 1 / l2;
  return (x, y, z) => {
    const pax = x - a[0], pay = y - a[1], paz = z - a[2];
    const yv = pax * bax + pay * bay + paz * baz;
    const zv = yv - l2;
    const qx = pax * l2 - bax * yv, qy = pay * l2 - bay * yv, qz = paz * l2 - baz * yv;
    const x2 = qx * qx + qy * qy + qz * qz;
    const y2 = yv * yv * l2;
    const z2 = zv * zv * l2;
    const k = Math.sign(rr) * rr * rr * x2;
    if (Math.sign(zv) * a2 * z2 > k) return Math.sqrt(x2 + z2) * il2 - r2;
    if (Math.sign(yv) * a2 * y2 < k) return Math.sqrt(x2 + y2) * il2 - r1;
    return (Math.sqrt(x2 * a2 * il2) + yv * rr) * il2 - r1;
  };
}

/** Elipsoide (aproximación de IQ) / Ellipsoid (IQ's approximation). */
export function ellipsoid(c, r) {
  const i0 = 1 / r[0], i1 = 1 / r[1], i2 = 1 / r[2];
  const j0 = i0 * i0, j1 = i1 * i1, j2 = i2 * i2;
  return (x, y, z) => {
    const px = x - c[0], py = y - c[1], pz = z - c[2];
    const ax = px * i0, ay = py * i1, az = pz * i2;
    const bx = px * j0, by = py * j1, bz = pz * j2;
    const k0 = Math.sqrt(ax * ax + ay * ay + az * az);
    const k1 = Math.sqrt(bx * bx + by * by + bz * bz);
    return k1 === 0 ? -Math.min(r[0], r[1], r[2]) : (k0 * (k0 - 1)) / k1;
  };
}

/** Caja redondeada / Rounded box. */
export function roundBox(c, half, r) {
  return (x, y, z) => {
    const qx = Math.abs(x - c[0]) - half[0] + r;
    const qy = Math.abs(y - c[1]) - half[1] + r;
    const qz = Math.abs(z - c[2]) - half[2] + r;
    const ox = Math.max(qx, 0), oy = Math.max(qy, 0), oz = Math.max(qz, 0);
    return Math.sqrt(ox * ox + oy * oy + oz * oz) + Math.min(Math.max(qx, qy, qz), 0) - r;
  };
}

/** Escala no uniforme alrededor de un punto (aprox. conservadora).
 *  Non-uniform scale around a point (conservative approximation). */
export function scaled(f, s, c = [0, 0, 0]) {
  const m = Math.min(s[0], s[1], s[2]);
  return (x, y, z) => f(
    c[0] + (x - c[0]) / s[0],
    c[1] + (y - c[1]) / s[1],
    c[2] + (z - c[2]) / s[2],
  ) * m;
}

// ---------------------------------------------------------------- mallado / meshing

/**
 * Convierte un SDF en BufferGeometry con surface nets.
 * Meshes an SDF into a BufferGeometry using surface nets.
 *
 * @param {(x:number,y:number,z:number)=>number} sdf
 * @param {{min:number[], max:number[]}} box
 * @param {number} cell  tamaño de celda / cell size
 * @param {(p:THREE.Vector3, n:THREE.Vector3, ao:number)=>number[]} [colorOf]
 */
export function meshSDF(sdf, box, cell, colorOf) {
  const nx = Math.ceil((box.max[0] - box.min[0]) / cell) + 1;
  const ny = Math.ceil((box.max[1] - box.min[1]) / cell) + 1;
  const nz = Math.ceil((box.max[2] - box.min[2]) / cell) + 1;
  const ox = box.min[0], oy = box.min[1], oz = box.min[2];
  const field = new Float32Array(nx * ny * nz);
  const idx = (i, j, k) => i + nx * (j + ny * k);

  // ES: Banda estrecha: primero una rejilla gruesa; solo se evalúa en fino
  //     donde la superficie puede pasar. Evita ~80 % de las evaluaciones.
  // EN: Narrow band: coarse grid first; fine evaluation only where the
  //     surface can pass. Skips ~80 % of the evaluations.
  const S = 4;
  const cx = Math.ceil((nx - 1) / S) + 1, cy = Math.ceil((ny - 1) / S) + 1, cz = Math.ceil((nz - 1) / S) + 1;
  const coarse = new Float32Array(cx * cy * cz);
  const cid = (i, j, k) => i + cx * (j + cy * k);
  for (let k = 0; k < cz; k++) {
    for (let j = 0; j < cy; j++) {
      for (let i = 0; i < cx; i++) coarse[cid(i, j, k)] = sdf(ox + i * S * cell, oy + j * S * cell, oz + k * S * cell);
    }
  }
  const safe = S * cell * 1.9;
  const done = new Uint8Array(nx * ny * nz);
  for (let K = 0; K < cz - 1; K++) {
    for (let J = 0; J < cy - 1; J++) {
      for (let I = 0; I < cx - 1; I++) {
        let lo = Infinity, sgn = 0, mixed = false;
        for (let c = 0; c < 8; c++) {
          const d = coarse[cid(I + (c & 1), J + ((c >> 1) & 1), K + ((c >> 2) & 1))];
          const s2 = d < 0 ? -1 : 1;
          if (sgn === 0) sgn = s2; else if (s2 !== sgn) mixed = true;
          lo = Math.min(lo, Math.abs(d));
        }
        const exact = mixed || lo < safe;
        const i1 = Math.min(nx - 1, (I + 1) * S), j1 = Math.min(ny - 1, (J + 1) * S), k1 = Math.min(nz - 1, (K + 1) * S);
        for (let k = K * S; k <= k1; k++) {
          const z = oz + k * cell;
          for (let j = J * S; j <= j1; j++) {
            const y = oy + j * cell;
            for (let i = I * S; i <= i1; i++) {
              const o = idx(i, j, k);
              if (done[o] === 2 || (done[o] === 1 && !exact)) continue;
              if (exact) { field[o] = sdf(ox + i * cell, y, z); done[o] = 2; }
              else { field[o] = sgn * lo; done[o] = 1; }
            }
          }
        }
      }
    }
  }

  // Un vértice por celda con cambio de signo / One vertex per sign-changing cell.
  const cellVert = new Int32Array((nx - 1) * (ny - 1) * (nz - 1)).fill(-1);
  const cidx = (i, j, k) => i + (nx - 1) * (j + (ny - 1) * k);
  const pos = [];
  // Esquinas y aristas del cubo en forma plana / Cube corners and edges, flattened.
  const CX = [0, 1, 0, 1, 0, 1, 0, 1], CY = [0, 0, 1, 1, 0, 0, 1, 1], CZ = [0, 0, 0, 0, 1, 1, 1, 1];
  const E0 = [0, 2, 4, 6, 0, 1, 4, 5, 0, 1, 2, 3], E1 = [1, 3, 5, 7, 2, 3, 6, 7, 4, 5, 6, 7];
  const coff = CX.map((_, c) => CX[c] + nx * (CY[c] + ny * CZ[c]));
  const v = new Float32Array(8);

  for (let k = 0; k < nz - 1; k++) {
    for (let j = 0; j < ny - 1; j++) {
      let base = idx(0, j, k);
      for (let i = 0; i < nx - 1; i++, base++) {
        let neg = 0;
        for (let c = 0; c < 8; c++) {
          const d = field[base + coff[c]];
          v[c] = d;
          if (d < 0) neg++;
        }
        if (neg === 0 || neg === 8) continue;
        let sx = 0, sy = 0, sz = 0, n = 0;
        for (let e = 0; e < 12; e++) {
          const e0 = E0[e], e1 = E1[e];
          const a0 = v[e0], a1 = v[e1];
          if ((a0 < 0) === (a1 < 0)) continue;
          const t = a0 / (a0 - a1);
          sx += CX[e0] + (CX[e1] - CX[e0]) * t;
          sy += CY[e0] + (CY[e1] - CY[e0]) * t;
          sz += CZ[e0] + (CZ[e1] - CZ[e0]) * t;
          n++;
        }
        cellVert[cidx(i, j, k)] = pos.length / 3;
        pos.push(ox + (i + sx / n) * cell, oy + (j + sy / n) * cell, oz + (k + sz / n) * cell);
      }
    }
  }

  // Un quad por arista con cambio de signo / One quad per sign-changing edge.
  const index = [];
  const quad = (a, b, c, d, flip) => {
    if (a < 0 || b < 0 || c < 0 || d < 0) return;
    if (flip) index.push(a, c, b, a, d, c);
    else index.push(a, b, c, a, c, d);
  };
  for (let k = 1; k < nz - 1; k++) {
    for (let j = 1; j < ny - 1; j++) {
      for (let i = 1; i < nx - 1; i++) {
        const inside = field[idx(i, j, k)] < 0;
        if (i < nx - 1 && inside !== (field[idx(i + 1, j, k)] < 0)) {
          quad(cellVert[cidx(i, j - 1, k - 1)], cellVert[cidx(i, j, k - 1)],
            cellVert[cidx(i, j, k)], cellVert[cidx(i, j - 1, k)], !inside);
        }
        if (j < ny - 1 && inside !== (field[idx(i, j + 1, k)] < 0)) {
          quad(cellVert[cidx(i - 1, j, k - 1)], cellVert[cidx(i - 1, j, k)],
            cellVert[cidx(i, j, k)], cellVert[cidx(i, j, k - 1)], !inside);
        }
        if (k < nz - 1 && inside !== (field[idx(i, j, k + 1)] < 0)) {
          quad(cellVert[cidx(i - 1, j - 1, k)], cellVert[cidx(i, j - 1, k)],
            cellVert[cidx(i, j, k)], cellVert[cidx(i - 1, j, k)], !inside);
        }
      }
    }
  }

  // Proyección a la superficie y normales del gradiente.
  // Project onto the surface and take normals from the gradient.
  const h = cell * 0.35;
  const grad = (x, y, z, out) => {
    // tetraedro: 4 evaluaciones / tetrahedron: 4 evaluations
    const a = sdf(x + h, y - h, z - h), b = sdf(x - h, y - h, z + h);
    const c = sdf(x - h, y + h, z - h), d = sdf(x + h, y + h, z + h);
    out.set(a - b - c + d, -a - b + c + d, -a + b - c + d);
    const l = out.length();
    return l > 0 ? out.multiplyScalar(1 / l) : out.set(0, 1, 0);
  };
  const g = new THREE.Vector3();
  const p = new THREE.Vector3();
  const count = pos.length / 3;
  const normals = new Float32Array(count * 3);
  const colors = colorOf ? new Float32Array(count * 3) : null;
  const positions = new Float32Array(pos);
  for (let q = 0; q < count; q++) {
    p.fromArray(positions, q * 3);
    grad(p.x, p.y, p.z, g);
    p.addScaledVector(g, -sdf(p.x, p.y, p.z));
    p.toArray(positions, q * 3);
    g.toArray(normals, q * 3);
    if (colors) {
      // Oclusión ambiental a partir del propio campo / Ambient occlusion from the field itself.
      let occ = 0, w = 1;
      for (let s = 1; s <= 4; s++) {
        const dist = 0.15 * s;
        occ += w * (dist - sdf(p.x + g.x * dist, p.y + g.y * dist, p.z + g.z * dist));
        w *= 0.6;
      }
      const ao = Math.min(1, Math.max(0, 1 - 1.6 * occ));
      const rgb = colorOf(p, g, ao);
      colors[q * 3] = rgb[0];
      colors[q * 3 + 1] = rgb[1];
      colors[q * 3 + 2] = rgb[2];
    }
  }

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geo.setAttribute('normal', new THREE.BufferAttribute(normals, 3));
  if (colors) geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  geo.setIndex(count > 65535 ? new THREE.Uint32BufferAttribute(index, 1) : new THREE.Uint16BufferAttribute(index, 1));
  geo.computeBoundingSphere();
  return geo;
}
