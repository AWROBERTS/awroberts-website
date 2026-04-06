let soundStarted = false;

let diag;

let audioCtx;
let masterGain;
let dryGain;
let wetGain;
let convolver;
let delayNode;
let delayFeedback;
let voiceGain;
let bassGain;

let melodyOsc;
let harmonyOsc;
let bassOsc;
let lfo;
let lfoGain;

let updateTimer = null;
let streamRedSample = 0.35;

let melodyNotes = [];
let rhythmSeed = 1;
let clusterSeed = 1;

let sampleVideoEl = null;
let sampleVideoReady = false;
let sampleVideoCanvas = null;
let sampleVideoCtx = null;

let sampleHls = null;

const STREAM_URL = "https://awroberts.co.uk/stream/index.m3u8?v=" + Date.now();

function preload() {
  diag = loadJSON('/deployment.json');
}

function setup() {
  const canvas = createCanvas(windowWidth, windowHeight);
  canvas.parent('canvas-container');
  noStroke();

  const btn = document.getElementById('start-button');
  if (btn) {
    btn.addEventListener('click', startSound);
  }

  setupStreamSampler();
}

function draw() {
  background(0);

  // subtle live backdrop
  fill(0, 50);
  rect(0, 0, width, height);

  const t = millis() * 0.001;
  fill(127, 203, 255);
  circle(width / 2 + sin(t * 0.8) * 70, height / 2 + cos(t * 1.1) * 40, 38);

  fill(255);
  textAlign(CENTER, CENTER);
  textSize(18);
  text(
    soundStarted ? 'sound running' : 'click the button to start sound',
    width / 2,
    height * 0.82
  );
}

function setupStreamSampler() {
  sampleVideoEl = document.createElement('video');
  sampleVideoEl.crossOrigin = 'anonymous';
  sampleVideoEl.muted = true;
  sampleVideoEl.playsInline = true;
  sampleVideoEl.autoplay = true;
  sampleVideoEl.preload = 'auto';
  sampleVideoEl.loop = true;
  sampleVideoEl.style.display = 'none';

  document.body.appendChild(sampleVideoEl);

  sampleVideoCanvas = document.createElement('canvas');
  sampleVideoCtx = sampleVideoCanvas.getContext('2d', { willReadFrequently: true });

  const markReady = () => {
    sampleVideoReady = true;
  };

  sampleVideoEl.addEventListener('loadeddata', markReady);
  sampleVideoEl.addEventListener('canplay', markReady);
  sampleVideoEl.addEventListener('playing', markReady);

  if (window.Hls && Hls.isSupported()) {
    sampleHls = new Hls({
      enableWorker: true,
      lowLatencyMode: false,
      maxBufferLength: 30,
      backBufferLength: 0
    });

    sampleHls.loadSource(STREAM_URL);
    sampleHls.attachMedia(sampleVideoEl);
  } else if (sampleVideoEl.canPlayType('application/vnd.apple.mpegurl')) {
    sampleVideoEl.src = STREAM_URL;
  } else {
    console.warn('No HLS support available for stream sampler');
  }
}

async function startSound() {
  if (soundStarted) return;
  soundStarted = true;

  const overlay = document.getElementById('start-overlay');
  if (overlay) overlay.style.display = 'none';

  audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  await audioCtx.resume();

  buildSeeds();
  buildMelodyFromSha();
  streamRedSample = sampleStreamRed();
  buildAudioGraph();
  startScheduler();
}

function buildSeeds() {
  const sha = String(diag?.awroberts?.build?.sha ?? 'abcdef0123456789');
  const podIp = String(diag?.pod?.ip ?? '10.0.0.1');
  const clusterIp = String(diag?.awroberts?.service?.clusterIP ?? '10.96.0.1');

  rhythmSeed = numericSeedFromString(podIp);
  clusterSeed = numericSeedFromString(clusterIp) ^ numericSeedFromString(sha);
}

function buildMelodyFromSha() {
  const sha = String(diag?.awroberts?.build?.sha ?? 'abcdef0123456789');

  const degrees = [];
  for (let i = 0; i < sha.length; i++) {
    const c = sha[i].toLowerCase();
    const v = parseInt(c, 16);
    if (Number.isFinite(v)) degrees.push(v);
  }

  const scale = [0, 2, 3, 5, 7, 10, 12, 14];
  melodyNotes = [];

  for (let i = 0; i < degrees.length; i += 2) {
    const a = degrees[i] ?? 0;
    const b = degrees[i + 1] ?? 0;
    const degree = scale[(a + b) % scale.length];
    const octave = 2 + ((a ^ b) % 3);
    const midi = 48 + degree + octave * 12;
    const freq = midiToFreq(midi);

    if (Number.isFinite(freq)) {
      melodyNotes.push(freq);
    }
  }

  if (melodyNotes.length < 4) {
    melodyNotes = [110, 130.81, 146.83, 164.81, 196, 220];
  }
}

function buildAudioGraph() {
  masterGain = audioCtx.createGain();
  masterGain.gain.value = 0.8;
  masterGain.connect(audioCtx.destination);

  dryGain = audioCtx.createGain();
  dryGain.gain.value = 0.62;
  dryGain.connect(masterGain);

  wetGain = audioCtx.createGain();
  wetGain.gain.value = 0.38;
  wetGain.connect(masterGain);

  delayNode = audioCtx.createDelay(2.0);
  delayNode.delayTime.value = 0.24 + (clusterSeed % 7) * 0.03;

  delayFeedback = audioCtx.createGain();
  delayFeedback.gain.value = 0.28 + (rhythmSeed % 5) * 0.03;

  delayNode.connect(delayFeedback);
  delayFeedback.connect(delayNode);
  delayNode.connect(wetGain);

  convolver = audioCtx.createConvolver();
  convolver.buffer = makeImpulseResponse(audioCtx, 2.8, 2.2, streamRedSample);
  convolver.connect(wetGain);

  melodyOsc = audioCtx.createOscillator();
  melodyOsc.type = 'sine';

  harmonyOsc = audioCtx.createOscillator();
  harmonyOsc.type = 'triangle';

  voiceGain = audioCtx.createGain();
  voiceGain.gain.value = 0.0;

  melodyOsc.connect(voiceGain);
  harmonyOsc.connect(voiceGain);

  voiceGain.connect(dryGain);
  voiceGain.connect(delayNode);
  voiceGain.connect(convolver);

  bassOsc = audioCtx.createOscillator();
  bassOsc.type = 'sine';

  bassGain = audioCtx.createGain();
  bassGain.gain.value = 0.0;

  bassOsc.connect(bassGain);
  bassGain.connect(dryGain);

  lfo = audioCtx.createOscillator();
  lfo.type = 'sine';
  lfo.frequency.value = 0.05 + (clusterSeed % 4) * 0.01;

  lfoGain = audioCtx.createGain();
  lfoGain.gain.value = 14 + (rhythmSeed % 6) * 2;

  lfo.connect(lfoGain);
  lfoGain.connect(melodyOsc.frequency);
  lfoGain.connect(harmonyOsc.frequency);

  melodyOsc.start();
  harmonyOsc.start();
  bassOsc.start();
  lfo.start();

  const now = audioCtx.currentTime;
  voiceGain.gain.setValueAtTime(0.0, now);
  voiceGain.gain.linearRampToValueAtTime(0.18, now + 2.5);
  bassGain.gain.setValueAtTime(0.0, now);
  bassGain.gain.linearRampToValueAtTime(0.08, now + 4.0);

  setMelodyStep(0);
}

function startScheduler() {
  const baseMs = 700 + (rhythmSeed % 7) * 90 + (clusterSeed % 5) * 25;
  const jitter = 120 + (clusterSeed % 3) * 40;
  let step = 0;

  updateTimer = setInterval(() => {
    if (!soundStarted || !audioCtx) return;

    streamRedSample = sampleStreamRed();
    updateReverbFromRed(streamRedSample);

    setMelodyStep(step);

    const now = audioCtx.currentTime;
    const pulse = 0.10 + (rhythmSeed % 9) * 0.006 + Math.random() * 0.03;

    voiceGain.gain.cancelScheduledValues(now);
    voiceGain.gain.setTargetAtTime(pulse, now, 0.05);
    voiceGain.gain.setTargetAtTime(0.18, now + 0.18, 0.12);

    bassGain.gain.cancelScheduledValues(now);
    bassGain.gain.setTargetAtTime(0.06 + ((clusterSeed + step) % 4) * 0.01, now, 0.08);

    step++;
  }, baseMs + Math.floor(Math.random() * jitter));
}

function setMelodyStep(step) {
  if (!audioCtx || melodyNotes.length === 0) return;

  const safeLen = melodyNotes.length;
  const idx = (((step * 3) + rhythmSeed + clusterSeed) % safeLen + safeLen) % safeLen;
  const noteRaw = melodyNotes[idx];
  const note = Number.isFinite(noteRaw) ? noteRaw : 110;
  const harmony = Number.isFinite(note * 2) ? note * 2 : 220;

  const bassChoices = [55, 61.74, 65.41, 73.42];
  const bassIdx = (((step + clusterSeed) % bassChoices.length) + bassChoices.length) % bassChoices.length;
  const bassFreqRaw = bassChoices[bassIdx];
  const bassFreq = Number.isFinite(bassFreqRaw) ? bassFreqRaw : 55;

  if (![note, harmony, bassFreq].every(Number.isFinite)) {
    console.warn('Non-finite frequency detected', { step, idx, noteRaw, note, harmony, bassFreqRaw, bassFreq });
    return;
  }

  const now = audioCtx.currentTime;
  melodyOsc.frequency.cancelScheduledValues(now);
  harmonyOsc.frequency.cancelScheduledValues(now);
  bassOsc.frequency.cancelScheduledValues(now);

  melodyOsc.frequency.linearRampToValueAtTime(note, now + 0.25);
  harmonyOsc.frequency.linearRampToValueAtTime(harmony, now + 0.25);
  bassOsc.frequency.linearRampToValueAtTime(bassFreq, now + 0.35);
}

function updateReverbFromRed(redAmount) {
  if (!audioCtx || !convolver || !wetGain) return;

  const safeRed = Number.isFinite(redAmount) ? clamp(redAmount, 0, 1) : 0.35;
  const wet = clamp(0.08 + safeRed * 0.62, 0.06, 0.78);
  const decay = 1.5 + safeRed * 3.5;

  wetGain.gain.cancelScheduledValues(audioCtx.currentTime);
  wetGain.gain.setTargetAtTime(wet, audioCtx.currentTime, 0.15);

  convolver.buffer = makeImpulseResponse(audioCtx, 2.6, decay, safeRed);
}

function sampleStreamRed() {
  if (!sampleVideoEl || !sampleVideoReady) return 0.35;
  if (!sampleVideoEl.videoWidth || !sampleVideoEl.videoHeight) return 0.35;

  const w = Math.min(96, sampleVideoEl.videoWidth);
  const h = Math.min(96, sampleVideoEl.videoHeight);

  if (sampleVideoCanvas.width !== w || sampleVideoCanvas.height !== h) {
    sampleVideoCanvas.width = w;
    sampleVideoCanvas.height = h;
  }

  try {
    sampleVideoCtx.drawImage(sampleVideoEl, 0, 0, w, h);
    const data = sampleVideoCtx.getImageData(0, 0, w, h).data;

    let sumR = 0;
    let count = 0;

    for (let i = 0; i < data.length; i += 4) {
      sumR += data[i];
      count++;
    }

    return count ? (sumR / count) / 255 : 0.35;
  } catch (err) {
    console.warn('Could not sample stream frame red channel:', err);
    return 0.35;
  }
}

function makeImpulseResponse(ctx, duration, decay, redAmount = 0.35) {
  const sampleRate = ctx.sampleRate;
  const length = Math.floor(sampleRate * duration);
  const buffer = ctx.createBuffer(2, length, sampleRate);

  for (let ch = 0; ch < 2; ch++) {
    const data = buffer.getChannelData(ch);
    for (let i = 0; i < length; i++) {
      const n = i / length;
      const colorWeight = 0.7 + redAmount * 0.6;
      data[i] = (Math.random() * 2 - 1) * Math.pow(1 - n, decay * colorWeight);
    }
  }

  return buffer;
}

function numericSeedFromString(str) {
  let out = 0;
  for (let i = 0; i < str.length; i++) {
    out = (out * 31 + str.charCodeAt(i)) >>> 0;
  }
  return out;
}

function midiToFreq(midi) {
  return 440 * Math.pow(2, (midi - 69) / 12);
}

function clamp(v, minV, maxV) {
  return Math.max(minV, Math.min(maxV, v));
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
}