let soundStarted = false;
let audioCtx;
let masterGain;
let oscA;
let oscB;
let lfo;
let lfoGain;
let delayNode;
let delayFeedback;
let convolver;
let wetGain;
let dryGain;
let bassOsc;
let bassGain;
let updateTimer;

function setup() {
  const canvas = createCanvas(windowWidth, windowHeight);
  canvas.parent('canvas-container');
  noStroke();

  const btn = document.getElementById('start-button');
  btn.addEventListener('click', startSound);
}

function draw() {
  background(0);

  fill(255);
  textAlign(CENTER, CENTER);
  textSize(24);
  text(soundStarted ? 'Sound is running' : 'Click to start sound', width / 2, height / 2);

  const t = millis() * 0.001;
  fill(127, 203, 255);
  circle(width / 2 + sin(t) * 80, height / 2 + cos(t * 1.3) * 50, 40);

  fill(255, 120);
  circle(width / 2 + cos(t * 0.7) * 130, height / 2 + sin(t * 0.9) * 90, 18);
}

async function startSound() {
  if (soundStarted) return;
  soundStarted = true;

  const overlay = document.getElementById('start-overlay');
  if (overlay) overlay.style.display = 'none';

  audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  await audioCtx.resume();

  masterGain = audioCtx.createGain();
  masterGain.gain.value = 0.8;
  masterGain.connect(audioCtx.destination);

  // dry / wet routing
  dryGain = audioCtx.createGain();
  dryGain.gain.value = 0.55;
  dryGain.connect(masterGain);

  wetGain = audioCtx.createGain();
  wetGain.gain.value = 0.45;

  delayNode = audioCtx.createDelay(2.0);
  delayNode.delayTime.value = 0.28;

  delayFeedback = audioCtx.createGain();
  delayFeedback.gain.value = 0.38;

  // delay loop
  delayNode.connect(delayFeedback);
  delayFeedback.connect(delayNode);
  delayNode.connect(wetGain);
  wetGain.connect(masterGain);

  // very small reverb-ish smear using a simple impulse
  convolver = audioCtx.createConvolver();
  convolver.buffer = makeImpulseResponse(audioCtx, 2.5, 2.0);
  convolver.connect(wetGain);

  // main voice
  oscA = audioCtx.createOscillator();
  oscA.type = 'sine';
  oscA.frequency.value = 110;

  oscB = audioCtx.createOscillator();
  oscB.type = 'triangle';
  oscB.frequency.value = 220;

  const voiceGain = audioCtx.createGain();
  voiceGain.gain.value = 0.0;

  oscA.connect(voiceGain);
  oscB.connect(voiceGain);

  voiceGain.connect(dryGain);
  voiceGain.connect(delayNode);
  voiceGain.connect(convolver);

  // bass bed
  bassOsc = audioCtx.createOscillator();
  bassOsc.type = 'sine';
  bassOsc.frequency.value = 55;

  bassGain = audioCtx.createGain();
  bassGain.gain.value = 0.0;
  bassOsc.connect(bassGain);
  bassGain.connect(dryGain);

  // low-frequency wobble
  lfo = audioCtx.createOscillator();
  lfo.type = 'sine';
  lfo.frequency.value = 0.06;

  lfoGain = audioCtx.createGain();
  lfoGain.gain.value = 18;

  lfo.connect(lfoGain);
  lfoGain.connect(oscA.frequency);
  lfoGain.connect(oscB.frequency);

  oscA.start();
  oscB.start();
  bassOsc.start();
  lfo.start();

  // fade in
  voiceGain.gain.setValueAtTime(0.0, audioCtx.currentTime);
  voiceGain.gain.linearRampToValueAtTime(0.18, audioCtx.currentTime + 3.0);
  bassGain.gain.setValueAtTime(0.0, audioCtx.currentTime);
  bassGain.gain.linearRampToValueAtTime(0.08, audioCtx.currentTime + 4.0);

  // periodic movement
  updateTimer = setInterval(() => {
    if (!soundStarted) return;

    const melody = [110, 130.81, 146.83, 164.81, 196, 220, 261.63];
    const nextA = melody[Math.floor(Math.random() * melody.length)];
    const nextB = nextA * 2;

    const now = audioCtx.currentTime;
    oscA.frequency.cancelScheduledValues(now);
    oscB.frequency.cancelScheduledValues(now);
    oscA.frequency.linearRampToValueAtTime(nextA, now + 0.35);
    oscB.frequency.linearRampToValueAtTime(nextB, now + 0.35);

    // subtle amplitude pulse
    const pulse = 0.12 + Math.random() * 0.08;
    voiceGain.gain.cancelScheduledValues(now);
    voiceGain.gain.setTargetAtTime(pulse, now, 0.08);
    voiceGain.gain.setTargetAtTime(0.18, now + 0.22, 0.14);
  }, 1800);
}

function makeImpulseResponse(audioCtx, duration, decay) {
  const sampleRate = audioCtx.sampleRate;
  const length = sampleRate * duration;
  const buffer = audioCtx.createBuffer(2, length, sampleRate);

  for (let ch = 0; ch < 2; ch++) {
    const data = buffer.getChannelData(ch);
    for (let i = 0; i < length; i++) {
      const n = i / length;
      data[i] = (Math.random() * 2 - 1) * Math.pow(1 - n, decay);
    }
  }

  return buffer;
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
}