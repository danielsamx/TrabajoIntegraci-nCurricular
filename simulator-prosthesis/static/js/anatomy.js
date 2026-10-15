// Anatomía de la mano: medidas y marco de referencia, compartidos por los estilos.
// Hand anatomy: sizes and reference frame, shared by every style.
//
// ES: Marco de la mano: palma hacia +Z, dedos hacia +Y, pulgar (mano derecha)
//     hacia +X, muñeca hacia −Y. Las medidas están en centímetros. Los estilos
//     (humano, robótico) cambian el aspecto, no estas medidas ni la cinemática.
// EN: Hand frame: palm toward +Z, fingers +Y, thumb (right hand) +X, wrist −Y.
//     Sizes are in centimetres. Styles (human, robotic) change the looks, not
//     these sizes nor the kinematics.

export const PALETTE = {
  navy: 0x001f3f,
  pink: 0xd81b60,
  amber: 0xffc107,
  white: 0xffffff,
  black: 0x000000,
};

// ---------------------------------------------------------------- anatomía / anatomy (cm)

export const FLAT = 0.86; // los dedos son más anchos que gruesos / fingers are wider than thick

// Arco metacarpiano: los nudillos laterales quedan más hacia la palma.
// Metacarpal arch: the outer knuckles sit further toward the palm.
export const ARCH = 0.045;
export const arch = (x) => ARCH * x * x;

export const FINGERS = [
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

export const WRIST_Y = -3.4;          // corte de la muñeca / wrist cut
export const GROUND_Y = WRIST_Y;

// ES: Signo por articulación para que el ángulo positivo de la tabla vaya
//     hacia la palma. Para D0, −θ sobre Y lleva el pulgar al frente de la
//     palma (+Z): oposición.
// EN: Per-joint sign so the table's positive angle points toward the palm.
//     For D0, −θ about Y swings the thumb in front of the palm (+Z): opposition.
export const SIGN = { D0: -1 };
