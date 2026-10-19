// پل دوربین و MediaPipe؛ همه‌چیز محلی است و پردازش روی دستگاه انجام می‌شود.
import { PoseLandmarker, FilesetResolver } from './mediapipe/vision_bundle.mjs';

let lm, stream, raf, last = 0;
const video = document.createElement('video');
Object.assign(video, { autoplay: true, muted: true, playsInline: true });
video.style.cssText = 'width:100%;height:100%;object-fit:cover';

async function load() {
  const fs = await FilesetResolver.forVisionTasks('mediapipe/wasm');
  const make = (delegate) => PoseLandmarker.createFromOptions(fs, {
    baseOptions: { modelAssetPath: 'mediapipe/pose_landmarker_lite.task', delegate },
    runningMode: 'VIDEO', numPoses: 1,
  });
  try { lm = await make('GPU'); } catch (_) { lm = await make('CPU'); }
}

let ac;
function ctx() {
  ac ??= new (window.AudioContext || window.webkitAudioContext)();
  if (ac.state === 'suspended') ac.resume();
  return ac;
}

window.PoseBridge = {
  video,
  beep(freq, ms) {
    try {
      const c = ctx(), o = c.createOscillator(), g = c.createGain();
      o.frequency.value = freq; g.gain.value = 0.25;
      o.connect(g); g.connect(c.destination);
      o.start(); o.stop(c.currentTime + ms / 1000);
    } catch (_) {}
  },
  say(text, lang, cut) {
    try {
      const s = window.speechSynthesis;
      if (!s) return false;
      if (cut) s.cancel();
      const u = new SpeechSynthesisUtterance(text);
      u.lang = lang; u.rate = 0.9;
      s.speak(u);
      return true;
    } catch (_) { return false; }
  },
  async start(cb, fps) {
    ctx(); // فعال‌سازی صدا هم‌زمان با لمس کاربر
    if (!lm) await load();
    stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 } }, audio: false,
    });
    video.srcObject = stream;
    await video.play();
    const step = (t) => {
      raf = requestAnimationFrame(step);
      if (t - last < 1000 / fps || video.readyState < 2) return;
      last = t;
      const l = lm.detectForVideo(video, t).landmarks[0];
      cb(l ? JSON.stringify(l.map(p => [+p.x.toFixed(4), +p.y.toFixed(4), +(p.visibility ?? 0).toFixed(3)])) : '');
    };
    raf = requestAnimationFrame(step);
  },
  stop() {
    cancelAnimationFrame(raf);
    stream?.getTracks().forEach(t => t.stop());
    video.srcObject = null;
  },
};
