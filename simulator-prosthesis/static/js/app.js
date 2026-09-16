// Página del simulador: la escena ocupa la pantalla y el panel se pliega.
// Simulator page: the scene fills the screen and the panel folds away.
//
// ES: La página no envía comandos ni pregunta por el estado en bucle: recibe
//     por WebSocket y anima. Solo lee /api/spec una vez al cargar.
// EN: The page neither sends commands nor polls: it receives over WebSocket and
//     animates. It reads /api/spec once on load.

import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { buildHand, GROUND_Y } from './hand.js';
import { ActuatorAnimator } from './motion.js';

const params = new URLSearchParams(location.search);
const LANG = params.get('lang') === 'en' ? 'en' : 'es';

const TEXT = {
  es: {
    title: 'Mano protésica', panel: 'Estado', toggle: 'Panel de estado (I)', close: 'Cerrar',
    hint: 'Arrastra para orbitar · rueda para acercar · doble clic para centrar',
    loading: 'Generando la mano…',
    connection: 'Conexión', profile: 'Perfil de límites', motion: 'Movimiento', origin: 'Origen de encóderes',
    finger: 'Dedo', counts: 'Cuentas', norm: 'Norm.', range: 'Rango', last: 'Último comando',
    highlight: 'Teñir el dedo que se mueve',
    shortcut: 'Tecla <kbd>I</kbd> abre y cierra este panel · <kbd>Esc</kbd> lo cierra',
    connected: 'conectado', connecting: 'conectando…', disconnected: 'sin conexión',
    moving: 'en curso', still: 'quieta', factory: 'de fábrica',
    recalibrated: 'recalibrado (X)', accepted: 'ACEPTADO', rejected: 'RECHAZADO',
    none: 'Aún no se ha recibido ningún comando.', stage: 'etapa', duration: 'duración',
    outside: 'fuera del perfil', gesture: 'gesto', action: 'acción',
    motions: { 'flexion/extension': 'flexión', 'rotation/opposition': 'oposición' },
    actions: { STOP: 'parada: congelada donde estaba', CALIBRATE: 'cero de encóderes fijado aquí', INIT_SHIELDS: 'drivers reinicializados' },
    profileChanged: (p, out) => out.length
      ? `Perfil cambiado a ${p}. La mano no se movió; fuera del envolvente: ${out.join(', ')}.`
      : `Perfil cambiado a ${p}. La pose actual está dentro.`,
  },
  en: {
    title: 'Prosthetic hand', panel: 'Status', toggle: 'Status panel (I)', close: 'Close',
    hint: 'Drag to orbit · wheel to zoom · double-click to recentre',
    loading: 'Building the hand…',
    connection: 'Connection', profile: 'Limit profile', motion: 'Motion', origin: 'Encoder origin',
    finger: 'Finger', counts: 'Counts', norm: 'Norm.', range: 'Range', last: 'Last command',
    highlight: 'Tint the moving finger',
    shortcut: 'Key <kbd>I</kbd> opens and closes this panel · <kbd>Esc</kbd> closes it',
    connected: 'connected', connecting: 'connecting…', disconnected: 'disconnected',
    moving: 'in progress', still: 'still', factory: 'factory',
    recalibrated: 'recalibrated (X)', accepted: 'ACCEPTED', rejected: 'REJECTED',
    none: 'No command received yet.', stage: 'stage', duration: 'duration',
    outside: 'outside profile', gesture: 'gesture', action: 'action',
    motions: { 'flexion/extension': 'flexion', 'rotation/opposition': 'opposition' },
    actions: { STOP: 'stop: frozen where it was', CALIBRATE: 'encoder zero set here', INIT_SHIELDS: 'drivers re-initialised' },
    profileChanged: (p, out) => out.length
      ? `Profile changed to ${p}. The hand did not move; outside the envelope: ${out.join(', ')}.`
      : `Profile changed to ${p}. The current pose is inside.`,
  },
};
const T = TEXT[LANG];
const HTML_KEYS = new Set(['shortcut']);

const $ = (id) => document.getElementById(id);
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* sin almacenamiento / no storage */ } },
};
const nextFrame = () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));

async function main() {
  document.documentElement.lang = LANG;
  document.querySelectorAll('[data-i18n]').forEach((el) => {
    const v = T[el.dataset.i18n];
    if (typeof v !== 'string') return;
    if (HTML_KEYS.has(el.dataset.i18n)) el.innerHTML = v; else el.textContent = v;
  });
  document.querySelectorAll('[data-i18n-title]').forEach((el) => {
    el.title = T[el.dataset.i18nTitle];
    el.setAttribute('aria-label', T[el.dataset.i18nTitle]);
  });
  document.title = LANG === 'en' ? 'Prosthetic hand simulator' : 'Simulador de mano protésica';

  const spec = await (await fetch('/api/spec')).json();
  const letters = spec.actuators.map((a) => a.letter);

  // ---------------------------------------------------------------- escena / scene
  const stage = $('stage');
  const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setClearColor(0xffffff, 1);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.NeutralToneMapping;
  renderer.toneMappingExposure = 1.0;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.VSMShadowMap;
  // ES: Se dibuja solo cuando algo cambia (cámara, pose, tinte); en reposo no gasta GPU.
  // EN: Draw only when something changes (camera, pose, tint); idle costs no GPU.
  renderer.shadowMap.autoUpdate = false;
  let dirty = true;
  let viewShift = 0; // px, desplazamiento de la vista / view offset
  stage.append(renderer.domElement);

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0xffffff);
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = 0.7;

  // Luz principal con sombra suave sobre el suelo / Key light with a soft floor shadow.
  const key = new THREE.DirectionalLight(0xfff3ea, 2.3);
  key.position.set(14, 26, -12);
  key.castShadow = true;
  key.shadow.mapSize.set(2048, 2048);
  key.shadow.camera.left = -18;
  key.shadow.camera.right = 18;
  key.shadow.camera.top = 22;
  key.shadow.camera.bottom = -14;
  key.shadow.camera.near = 1;
  key.shadow.camera.far = 80;
  key.shadow.radius = 10;
  key.shadow.blurSamples = 20;
  key.shadow.bias = -0.0004;
  key.target.position.set(0, 5, 0);
  scene.add(key, key.target);
  const fill = new THREE.DirectionalLight(0xe8f0ff, 0.6);
  fill.position.set(-16, 8, -6);
  scene.add(fill);
  const rim = new THREE.DirectionalLight(0xffe2d6, 0.9);
  rim.position.set(-4, 14, 20);
  scene.add(rim);

  const ground = new THREE.Mesh(new THREE.PlaneGeometry(240, 240), new THREE.ShadowMaterial({ opacity: 0.13 }));
  ground.rotation.x = -Math.PI / 2;
  ground.position.y = GROUND_Y;
  ground.receiveShadow = true;
  scene.add(ground);

  // Vista tres cuartos por el dorso, como una mano mostrada al observador.
  // Three-quarter view of the back of the hand.
  const camera = new THREE.PerspectiveCamera(30, 1, 0.5, 400);
  // ?view=back (defecto) | palm | side
  const VIEWS = {
    back: { pos: new THREE.Vector3(-17, 21, -52), target: new THREE.Vector3(1.6, 8.6, 0) },
    palm: { pos: new THREE.Vector3(14, 19, 52), target: new THREE.Vector3(1.6, 8.6, 0) },
    side: { pos: new THREE.Vector3(56, 18, 10), target: new THREE.Vector3(1.6, 8.6, 0) },
  };
  const HOME = VIEWS[params.get('view')] ?? VIEWS.back;
  camera.position.copy(HOME.pos);
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.target.copy(HOME.target);
  controls.enableDamping = true;
  controls.dampingFactor = 0.12;
  controls.autoRotate = false;
  controls.enablePan = true;
  controls.minDistance = 14;
  controls.maxDistance = 110;
  controls.maxPolarAngle = Math.PI * 0.62;
  controls.update();

  function resetView() {
    camera.position.copy(HOME.pos);
    controls.target.copy(HOME.target);
    controls.update();
  }
  renderer.domElement.addEventListener('dblclick', () => { resetView(); dirty = true; });
  const hint = $('hint');
  controls.addEventListener('start', () => { hint.dataset.hide = 'true'; });
  setTimeout(() => { hint.dataset.hide = 'true'; }, 9000);
  controls.addEventListener('change', () => { dirty = true; });

  function resize() {
    const w = stage.clientWidth, h = stage.clientHeight;
    renderer.setSize(w, h, false);
    dirty = true;
    camera.aspect = w / Math.max(1, h);
    // En pantallas estrechas se aleja la cámara para que quepa la mano.
    // On narrow screens the camera backs off so the hand fits.
    camera.fov = camera.aspect < 0.8 ? 42 : 30;
    if (viewShift) camera.setViewOffset(w, h, viewShift, 0, w, h);
    camera.updateProjectionMatrix();
  }
  new ResizeObserver(resize).observe(stage);
  resize();

  // La malla se genera al cargar; se deja pintar el aviso antes.
  // The mesh is generated on load; let the notice paint first.
  await nextFrame();
  const hand = buildHand(spec, { mirror: params.get('hand') === 'left', quality: Math.min(1.5, Math.max(0.4, Number(params.get('quality')) || 1)) });
  scene.add(hand.root);
  renderer.compile(scene, camera);
  $('loader').dataset.done = 'true';

  // ---------------------------------------------------------------- estado / state
  const anim = new ActuatorAnimator(letters);
  let profile = spec.default_profile;
  let calibrationOffset = Object.fromEntries(letters.map((k) => [k, 0]));
  let lastCommand = null;
  let notice = null; // aviso de cambio de perfil / profile-change notice
  const limitsOf = (k) => spec.profiles[profile][k];

  // ---------------------------------------------------------------- panel plegable / drawer
  const drawer = $('drawer');
  const toggle = $('toggle');
  function setDrawer(open) {
    drawer.setAttribute('aria-hidden', String(!open));
    document.body.dataset.drawer = open ? 'open' : 'closed';
    dirty = true;
    drawer.inert = !open;
    toggle.setAttribute('aria-expanded', String(open));
    store.set('sim.drawer', open ? '1' : '0');
    if (open) $('badge').hidden = true;
  }
  toggle.addEventListener('click', () => setDrawer(drawer.getAttribute('aria-hidden') === 'true'));
  $('close').addEventListener('click', () => setDrawer(false));
  window.addEventListener('keydown', (e) => {
    if (e.target instanceof HTMLInputElement || e.ctrlKey || e.metaKey || e.altKey) return;
    if (e.key === 'i' || e.key === 'I') setDrawer(drawer.getAttribute('aria-hidden') === 'true');
    else if (e.key === 'Escape') setDrawer(false);
  });
  setDrawer(store.get('sim.drawer') === '1');

  const highlight = $('highlight');
  highlight.addEventListener('change', () => { dirty = true; });
  highlight.checked = store.get('sim.highlight') !== '0';
  hand.setHighlight(highlight.checked);
  highlight.addEventListener('change', () => {
    hand.setHighlight(highlight.checked);
    store.set('sim.highlight', highlight.checked ? '1' : '0');
  });

  const rows = {};
  const tbody = $('rows');
  for (const a of spec.actuators) {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td><span class="letter">${a.letter}</span></td>
      <td>${LANG === 'en' ? a.finger : a.finger_es}<span class="sub">${a.finger_id} · ${T.motions[a.motion] ?? a.motion}</span></td>
      <td class="num" data-k="c">0</td>
      <td class="num" data-k="n">0.000</td>
      <td class="num" data-k="r">—</td>`;
    tbody.append(tr);
    rows[a.letter] = {
      tr, c: tr.querySelector('[data-k=c]'), n: tr.querySelector('[data-k=n]'), r: tr.querySelector('[data-k=r]'),
    };
  }

  const setText = (el, text) => { if (el.textContent !== text) el.textContent = text; };

  function renderStatic() {
    setText($('profile'), profile);
    const shifted = letters.filter((k) => calibrationOffset[k]);
    const origin = $('origin');
    if (shifted.length) {
      origin.innerHTML = '';
      const tag = document.createElement('span');
      tag.className = 'tag tag--amber';
      tag.textContent = T.recalibrated;
      origin.append(tag, document.createElement('br'),
        document.createTextNode(shifted.map((k) => `${k}+${calibrationOffset[k]}`).join(' ')));
    } else {
      setText(origin, T.factory);
    }
    for (const k of letters) {
      const { min, max } = limitsOf(k);
      setText(rows[k].r, `${min}–${max}`);
    }
    renderLast();
  }

  function describe(cmd) {
    if (!cmd) return '';
    if (!cmd.accepted) return `${T.stage} ${cmd.stage} · ${cmd.code} — ${cmd.message}`;
    const parts = [];
    if (cmd.gesture) parts.push(`${T.gesture}: ${cmd.gesture}`);
    if (cmd.action) parts.push(`${cmd.action} — ${T.actions[cmd.action] ?? ''}`);
    if (cmd.duration_ms) parts.push(`${cmd.duration_ms} ms`);
    return parts.join(' · ');
  }

  function renderLast() {
    const frame = $('last-frame');
    const verdict = $('last-verdict');
    const detail = $('last-detail');
    detail.removeAttribute('data-state');
    if (!lastCommand) {
      setText(frame, '—');
      verdict.hidden = true;
      detail.textContent = notice ?? T.none;
      if (notice) detail.dataset.state = 'warn';
      return;
    }
    frame.textContent = lastCommand.frame === '' ? '""' : lastCommand.frame;
    verdict.hidden = false;
    verdict.textContent = lastCommand.accepted ? T.accepted : T.rejected;
    verdict.dataset.state = lastCommand.accepted ? 'ok' : 'warn';
    detail.textContent = describe(lastCommand);
    if (!lastCommand.accepted) detail.dataset.state = 'warn';
    if (notice) {
      detail.dataset.state = 'warn';
      detail.textContent += `\n${notice}`;
    }
  }

  // Aviso breve abajo: se desvanece solo / Brief notice at the bottom: fades on its own.
  const toast = $('toast');
  let toastTimer = 0;
  // state: 'ok' | 'warn' (rechazo / rejection) | 'notice' (aviso sin rechazo / warning, not a rejection)
  function showToast(frame, detail, state) {
    const warn = state !== 'ok';
    $('toast-frame').textContent = frame;
    $('toast-detail').textContent = detail;
    toast.dataset.state = state;
    toast.dataset.show = 'true';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { toast.dataset.show = 'false'; }, warn ? 7000 : 2600);
    if (warn && drawer.getAttribute('aria-hidden') === 'true') $('badge').hidden = false;
  }

  // ---------------------------------------------------------------- mensajes / messages
  function onMessage(msg, now) {
    switch (msg.type) {
      case 'snapshot': {
        const s = msg.state;
        profile = s.profile;
        calibrationOffset = s.calibration_offset;
        lastCommand = s.last_command;
        notice = null;
        for (const k of letters) {
          const tr = s.trajectories[k];
          if (tr) anim.resume(k, tr, now);
          else anim.freeze(k, s.actuator_normalised[k], s.actuator_positions[k], now);
        }
        break;
      }
      case 'pose':
        for (const [k, n] of Object.entries(msg.target)) {
          anim.retarget(k, n, msg.target_counts[k], msg.duration_ms, now);
        }
        break;
      case 'stop':
        for (const k of letters) anim.freeze(k, msg.pose[k], msg.counts[k], now);
        break;
      case 'calibrated':
        calibrationOffset = msg.offset;
        for (const k of letters) anim.setCounts(k, msg.counts[k], now);
        break;
      case 'profile': {
        profile = msg.profile;
        const out = msg.out_of_envelope.map((o) => o.actuator);
        notice = T.profileChanged(profile, out);
        showToast(profile, notice, out.length ? 'notice' : 'ok');
        break;
      }
      case 'command':
        lastCommand = msg;
        notice = null;
        showToast(msg.frame === '' ? '""' : msg.frame, describe(msg), msg.accepted ? 'ok' : 'warn');
        break;
      default:
        return;
    }
    renderStatic();
  }

  // ---------------------------------------------------------------- WebSocket
  const conn = $('conn');
  function setConn(state) {
    conn.dataset.state = state === 'connected' ? 'ok' : 'off';
    conn.title = T[state];
    setText($('conn-text'), T[state]);
  }

  let backoff = 500;
  function connect() {
    setConn('connecting');
    const ws = new WebSocket(`${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws`);
    ws.onopen = () => { backoff = 500; setConn('connected'); };
    ws.onmessage = (ev) => onMessage(JSON.parse(ev.data), performance.now());
    ws.onclose = () => {
      setConn('disconnected');
      setTimeout(connect, backoff);
      backoff = Math.min(backoff * 2, 5000);
    };
  }
  connect();
  renderStatic();

  // ---------------------------------------------------------------- bucle / loop
  const normalised = {};
  const visual = {};
  const shown = {};
  const pill = $('motion-pill');
  const motionEl = $('motion');
  let last = performance.now();
  let lastMotionLabel = '';
  function frame() {
    const now = performance.now();
    const dt = Math.min(0.1, (now - last) / 1000);
    last = now;
    const moving = [];
    for (const k of letters) {
      const v = anim.valueAt(k, now);
      normalised[k] = v.n;
      const { min, max } = limitsOf(k);
      const c = Math.round(v.c);
      const outside = c < min || c > max || v.toC < min || v.toC > max;
      const isMoving = anim.isMoving(k, now);
      if (isMoving) moving.push(k);
      visual[k] = isMoving ? 'moving' : outside ? 'warn' : 'idle';

      const row = rows[k];
      if (row.tr.dataset.state !== visual[k]) row.tr.dataset.state = visual[k];
      row.tr.title = outside ? T.outside : '';
      setText(row.c, String(c));
      setText(row.n, v.n.toFixed(3));
    }
    hand.apply(normalised);
    const tinting = hand.paint(visual, dt);
    const poseChanged = letters.some((k) => normalised[k] !== shown[k]);
    for (const k of letters) shown[k] = normalised[k];

    const label = moving.length ? `${T.moving} · ${moving.join(' ')}` : T.still;
    if (label !== lastMotionLabel) {
      lastMotionLabel = label;
      motionEl.innerHTML = '';
      const tag = document.createElement('span');
      tag.className = moving.length ? 'tag tag--pink' : 'tag tag--navy';
      tag.textContent = label;
      motionEl.append(tag);
      pill.hidden = !moving.length;
      pill.textContent = moving.join(' ');
    }

    // Con el panel abierto la mano se desplaza hacia el espacio libre.
    // With the panel open the hand shifts into the free space.
    const wide = stage.clientWidth > 640;
    const wantShift = wide && document.body.dataset.drawer === 'open' ? 190 : 0;
    let shifting = false;
    if (Math.abs(wantShift - viewShift) > 0.5) {
      viewShift += (wantShift - viewShift) * Math.min(1, dt * 9);
      shifting = true;
    } else if (viewShift !== wantShift) {
      viewShift = wantShift;
      shifting = true;
    }
    if (shifting) {
      const w = stage.clientWidth, h = stage.clientHeight;
      if (viewShift === 0) camera.clearViewOffset();
      else camera.setViewOffset(w, h, viewShift, 0, w, h);
    }
    const cameraMoved = controls.update() || shifting;
    if (poseChanged) renderer.shadowMap.needsUpdate = true;
    if (dirty || poseChanged || tinting || cameraMoved) {
      if (dirty) renderer.shadowMap.needsUpdate = true;
      renderer.render(scene, camera);
      dirty = false;
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}

main().catch((err) => {
  console.error(err);
  const l = $('loader');
  l.dataset.done = 'false';
  l.textContent = String(err);
});
