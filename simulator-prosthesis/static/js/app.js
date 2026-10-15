// Página del simulador: la escena ocupa la pantalla; solo hay un aviso y unos ajustes.
// Simulator page: the scene fills the screen; there is only a notice and a few settings.
//
// ES: La página no envía comandos ni pregunta por el estado en bucle: recibe
//     por WebSocket y anima. Solo lee /api/spec una vez al cargar. El estado
//     completo (posiciones, perfil, calibración) vive en GET /api/state.
// EN: The page neither sends commands nor polls: it receives over WebSocket and
//     animates. It reads /api/spec once on load. The full state (positions,
//     profile, calibration) lives at GET /api/state.

import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { buildHand, GROUND_Y, STYLES } from './hand.js';
import { ActuatorAnimator } from './motion.js';

const params = new URLSearchParams(location.search);
const LANG = params.get('lang') === 'en' ? 'en' : 'es';

const TEXT = {
  es: {
    title: 'Mano protésica', toggle: 'Ajustes (I)',
    hint: 'Arrastra para orbitar · rueda para acercar · doble clic para centrar',
    loading: 'Generando la mano…',
    style: 'Estilo de la mano', styleHuman: 'Humana', styleRobot: 'Robótica',
    highlight: 'Teñir el dedo que se mueve',
    shortcut: 'Tecla <kbd>I</kbd> abre y cierra estos ajustes · <kbd>Esc</kbd> los cierra',
    connected: 'conectado', connecting: 'conectando…', disconnected: 'sin conexión',
    none: 'Aún no se ha recibido ningún comando.', stage: 'etapa',
    gesture: 'gesto',
    actions: { STOP: 'parada: congelada donde estaba', CALIBRATE: 'cero de encóderes fijado aquí', INIT_SHIELDS: 'drivers reinicializados' },
    profileChanged: (p, out) => out.length
      ? `Perfil cambiado a ${p}. La mano no se movió; fuera del envolvente: ${out.join(', ')}.`
      : `Perfil cambiado a ${p}. La pose actual está dentro.`,
  },
  en: {
    title: 'Prosthetic hand', toggle: 'Settings (I)',
    hint: 'Drag to orbit · wheel to zoom · double-click to recentre',
    loading: 'Building the hand…',
    style: 'Hand style', styleHuman: 'Human', styleRobot: 'Robotic',
    highlight: 'Tint the moving finger',
    shortcut: 'Key <kbd>I</kbd> opens and closes these settings · <kbd>Esc</kbd> closes them',
    connected: 'connected', connecting: 'connecting…', disconnected: 'disconnected',
    none: 'No command received yet.', stage: 'stage',
    gesture: 'gesture',
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
  $('style-group').setAttribute('aria-label', T.style);
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

  // Vista tres cuartos por el dorso / Three-quarter view of the back of the hand.
  // ?view=back (defecto) | palm | side
  const camera = new THREE.PerspectiveCamera(30, 1, 0.5, 400);
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
  controls.addEventListener('change', () => { dirty = true; });
  setTimeout(() => { hint.dataset.hide = 'true'; }, 9000);

  function resize() {
    const w = stage.clientWidth, h = stage.clientHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / Math.max(1, h);
    // En pantallas estrechas se abre el ángulo para que quepa la mano.
    // On narrow screens the field of view opens up so the hand fits.
    camera.fov = camera.aspect < 0.8 ? 42 : 30;
    camera.updateProjectionMatrix();
    dirty = true;
  }
  new ResizeObserver(resize).observe(stage);
  resize();

  // ---------------------------------------------------------------- estilos / styles
  const quality = Math.min(1.5, Math.max(0.4, Number(params.get('quality')) || 1));
  const mirror = params.get('hand') === 'left';
  const built = new Map();       // estilo → mano construida / style → built hand
  let hand = null;
  const loader = $('loader');

  async function useStyle(name) {
    if (hand && hand.style === name) return;
    if (!built.has(name)) {
      // Construir la malla tarda; se avisa y se deja pintar el aviso antes.
      // Building the mesh takes a moment; show the notice and let it paint first.
      loader.dataset.mode = built.size ? 'switch' : 'first';
      loader.dataset.done = 'false';
      await nextFrame();
      const fresh = buildHand(spec, { style: name, mirror, quality });
      scene.add(fresh.root);
      built.set(name, fresh);
      renderer.compile(scene, camera);
    }
    for (const [id, h] of built) h.root.visible = id === name;
    hand = built.get(name);
    hand.setHighlight(highlight.checked);
    hand.apply(normalised);
    loader.dataset.done = 'true';
    dirty = true;
    renderer.shadowMap.needsUpdate = true;
    store.set('sim.style', name);
    for (const b of styleButtons) b.setAttribute('aria-checked', String(b.dataset.style === name));
  }

  // ---------------------------------------------------------------- ajustes / settings
  const settings = $('settings');
  const toggle = $('toggle');
  function setSettings(open) {
    settings.setAttribute('aria-hidden', String(!open));
    settings.inert = !open;
    toggle.setAttribute('aria-expanded', String(open));
    store.set('sim.settings', open ? '1' : '0');
  }
  toggle.addEventListener('click', () => setSettings(settings.getAttribute('aria-hidden') === 'true'));
  window.addEventListener('keydown', (e) => {
    if (e.target instanceof HTMLInputElement || e.ctrlKey || e.metaKey || e.altKey) return;
    if (e.key === 'i' || e.key === 'I') setSettings(settings.getAttribute('aria-hidden') === 'true');
    else if (e.key === 'Escape') setSettings(false);
  });
  document.addEventListener('pointerdown', (e) => {
    if (settings.getAttribute('aria-hidden') === 'false'
      && !settings.contains(e.target) && !toggle.contains(e.target)) setSettings(false);
  });
  setSettings(store.get('sim.settings') === '1');

  const highlight = $('highlight');
  highlight.checked = store.get('sim.highlight') !== '0';
  highlight.addEventListener('change', () => {
    hand?.setHighlight(highlight.checked);
    store.set('sim.highlight', highlight.checked ? '1' : '0');
    dirty = true;
  });

  const styleButtons = [...$('style-group').querySelectorAll('button')];
  for (const b of styleButtons) b.addEventListener('click', () => useStyle(b.dataset.style));

  // ---------------------------------------------------------------- estado / state
  const anim = new ActuatorAnimator(letters);
  let profile = spec.default_profile;
  const normalised = Object.fromEntries(letters.map((k) => [k, 0]));
  const limitsOf = (k) => spec.profiles[profile][k];

  const requested = params.get('style');
  const chosen = STYLES[requested] ? requested : (STYLES[store.get('sim.style')] ? store.get('sim.style') : 'human');
  await useStyle(chosen);

  // ---------------------------------------------------------------- aviso / toast
  const toast = $('toast');
  let toastTimer = 0;
  // state: 'ok' | 'warn' (rechazo / rejection) | 'notice' (aviso sin rechazo / warning, not a rejection)
  function showToast(frame, detail, state) {
    $('toast-frame').textContent = frame;
    $('toast-detail').textContent = detail;
    toast.dataset.state = state;
    toast.dataset.show = 'true';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { toast.dataset.show = 'false'; }, state === 'ok' ? 2600 : 7000);
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

  // ---------------------------------------------------------------- mensajes / messages
  function onMessage(msg, now) {
    switch (msg.type) {
      case 'snapshot': {
        const s = msg.state;
        profile = s.profile;
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
        for (const k of letters) anim.setCounts(k, msg.counts[k], now);
        break;
      case 'profile': {
        profile = msg.profile;
        const out = msg.out_of_envelope.map((o) => o.actuator);
        showToast(profile, T.profileChanged(profile, out), out.length ? 'notice' : 'ok');
        break;
      }
      case 'command':
        showToast(msg.frame === '' ? '""' : msg.frame, describe(msg), msg.accepted ? 'ok' : 'warn');
        break;
      default:
        break;
    }
  }

  // ---------------------------------------------------------------- WebSocket
  const conn = $('conn');
  function setConn(state) {
    conn.dataset.state = state === 'connected' ? 'ok' : 'off';
    conn.title = T[state];
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

  // ---------------------------------------------------------------- bucle / loop
  const visual = {};
  const shown = {};
  const pill = $('motion-pill');
  let last = performance.now();
  let lastMotion = '';
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
    }
    hand.apply(normalised);
    const tinting = hand.paint(visual, dt);
    const poseChanged = letters.some((k) => normalised[k] !== shown[k]);
    for (const k of letters) shown[k] = normalised[k];

    const label = moving.join(' ');
    if (label !== lastMotion) {
      lastMotion = label;
      pill.hidden = !label;
      pill.textContent = label;
    }

    const cameraMoved = controls.update();
    if (poseChanged || dirty) renderer.shadowMap.needsUpdate = true;
    if (dirty || poseChanged || tinting || cameraMoved) {
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
