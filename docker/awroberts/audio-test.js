let bgVideoEl;
let hlsInstance = null;
let videoReady = false;
let videoFadeStart = null;
let videoFadeDuration = 1200;
let bgPosterImg = null;

// Full-resolution video source buffer
let videoSourceCanvas = null;
let videoSourceCtx = null;
let videoSourceReady = false;
let videoSourceWidth = 0;
let videoSourceHeight = 0;

// Persistent display buffer to keep the last good frame visible
let videoLayer = null;
let videoLayerCtx = null;
let videoLayerReady = false;
let lastVideoTime = -1;
let hasVideoFrame = false;

let curwenFont;
let emailText = 'info@awroberts.co.uk';
let emailSize;
let isHoveringEmail = false;

let diag;

let icons = {};
let socialLinks = [
  { imgKey: 'github', url: 'https://github.com/awroberts' },
  { imgKey: 'linkedin', url: 'https://www.linkedin.com/in/alexander-roberts-53563312b/' },
  { imgKey: 'bandcamp', url: 'https://chewvalleytapes.bandcamp.com/' }
];
let hoveringSocial = -1;

let fadeStartTime;

let audioCtx;
let soundStarted = false;
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

const glowColor = [127, 203, 255];
const VIDEO_URL = "https://awroberts.co.uk/stream/index.m3u8?v=" + Date.now();
const POSTER_URL = "/awroberts-media/background-poster.png";

function isMobileDevice() {
  return /Mobi|Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
}

function getOverlayPixelDensity() {
  if (!isMobileDevice()) return 1;
  return Math.min(window.devicePixelRatio || 1, 2);
}

function preload() {
  curwenFont = loadFont('/awroberts-media/CURWENFONT.ttf');
  diag = loadJSON('/deployment.json');

  bgPosterImg = loadImage(POSTER_URL);

  icons.github = loadImage('/assets/github.png');
  icons.linkedin = loadImage('/assets/linkedin.png');
  icons.bandcamp = loadImage('/assets/bandcamp.png');
}

function setup() {
  pixelDensity(getOverlayPixelDensity());

  const canvas = createCanvas(windowWidth, windowHeight);
  canvas.parent('canvas-container');
  canvas.style('position', 'absolute');
  canvas.style('top', '0');
  canvas.style('left', '0');
  canvas.style('z-index', '1');
  canvas.style('filter', 'saturate(1.8) contrast(1.08)');

  const elt = canvas.elt;
  if (elt) {
    elt.style.touchAction = 'none';
    elt.style.webkitTapHighlightColor = 'transparent';
  }

  videoSourceCanvas = document.createElement("canvas");
  videoSourceCtx = videoSourceCanvas.getContext("2d", { alpha: false });
  videoSourceReady = true;

  videoLayer = createGraphics(windowWidth, windowHeight);
  videoLayer.pixelDensity(1);
  videoLayer.clear();
  videoLayerReady = true;
  videoLayerCtx = videoLayer.drawingContext;

  bgVideoEl = document.getElementById("bg-video");

  if (bgVideoEl) {
    bgVideoEl.loop = false;
    bgVideoEl.muted = true;
    bgVideoEl.playsInline = true;
    bgVideoEl.autoplay = true;
    bgVideoEl.crossOrigin = "anonymous";

    bgVideoEl.addEventListener("loadstart", () => console.log("[video] loadstart"));
    bgVideoEl.addEventListener("loadedmetadata", () => console.log("[video] loadedmetadata", bgVideoEl.videoWidth, bgVideoEl.videoHeight));
    bgVideoEl.addEventListener("loadeddata", () => {
      console.log("[video] loadeddata");
      videoReady = true;
      bgVideoEl.play().catch(err => console.warn("[video] play() failed after loadeddata:", err));
    });
    bgVideoEl.addEventListener("canplay", () => {
      console.log("[video] canplay");
      videoReady = true;
      bgVideoEl.play().catch(err => console.warn("[video] play() failed after canplay:", err));
    });
    bgVideoEl.addEventListener("playing", () => {
      console.log("[video] playing");
      videoReady = true;
    });
    bgVideoEl.addEventListener("pause", () => console.log("[video] pause"));
    bgVideoEl.addEventListener("stalled", () => console.warn("[video] stalled"));
    bgVideoEl.addEventListener("waiting", () => console.warn("[video] waiting"));
    bgVideoEl.addEventListener("ended", () => {
      console.log("[video] ended; restarting");
      bgVideoEl.currentTime = 0;
      bgVideoEl.play().catch(err => console.warn("[video] restart play() failed:", err));
    });

    if (window.Hls && Hls.isSupported()) {
      hlsInstance = new Hls({
        enableWorker: true,
        lowLatencyMode: false,
        maxBufferLength: 60,
        maxBufferSize: 120 * 1000 * 1000,
        maxMaxBufferLength: 120,
        backBufferLength: 0,
        startPosition: 0
      });

      hlsInstance.on(Hls.Events.MEDIA_ATTACHED, () => {
        console.log("[hls] media attached");
      });

      hlsInstance.on(Hls.Events.MANIFEST_PARSED, () => {
        console.log("[hls] manifest parsed");
        bgVideoEl.play().catch(err => console.warn("[video] play() failed after manifest:", err));
      });

      hlsInstance.on(Hls.Events.ERROR, (event, data) => {
        console.warn("[hls] error:", data);
        if (data.fatal) {
          if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
            console.warn("[hls] recovering media error");
            hlsInstance.recoverMediaError();
          } else if (data.type === Hls.ErrorTypes.NETWORK_ERROR) {
            console.warn("[hls] restarting load");
            hlsInstance.startLoad();
          } else {
            console.warn("[hls] destroying instance due to fatal error");
            hlsInstance.destroy();
          }
        }
      });

      console.log("[hls] loading source:", VIDEO_URL);
      hlsInstance.loadSource(VIDEO_URL);
      hlsInstance.attachMedia(bgVideoEl);
    } else if (bgVideoEl.canPlayType("application/vnd.apple.mpegurl")) {
      console.log("[video] native HLS supported");
      bgVideoEl.src = VIDEO_URL;
      bgVideoEl.play().catch(err => console.warn("[video] native play() failed:", err));
    } else {
      console.warn("[video] no HLS support available");
    }
  }

  const btn = document.getElementById('start-button');
  if (btn) {
    btn.addEventListener('click', startSound);
  }

  emailSize = constrain(min(windowWidth, windowHeight) * 0.05, 16, 70);

  textFont(curwenFont);
  textSize(emailSize);
  textAlign(RIGHT, TOP);

  fadeStartTime = millis();
}

function draw() {
  clear();

  drawBackgroundFallback();

  if (videoReady && videoLayerReady) {
    const frameAvailable = updateVideoFrame();

    if (frameAvailable && hasVideoFrame) {
      let alpha = 255;
      if (videoFadeStart !== null) {
        const t = (millis() - videoFadeStart) / videoFadeDuration;
        alpha = constrain(t * 255, 0, 255);
      }

      push();
      tint(255, alpha);
      image(videoLayer, 0, 0, width, height);
      pop();
    }
  }

  drawEmail();
  drawSocialIcons();
  drawDeploymentInfo();
}

function updateVideoFrame() {
  if (!bgVideoEl) return false;
  if (!bgVideoEl.videoWidth || !bgVideoEl.videoHeight) return false;
  if (!videoSourceReady || !videoLayerReady) return false;

  const currentTime = bgVideoEl.currentTime;
  const hasAdvanced = currentTime !== lastVideoTime;

  if (hasVideoFrame && !hasAdvanced) return true;

  const sourceW = bgVideoEl.videoWidth;
  const sourceH = bgVideoEl.videoHeight;

  if (!sourceW || !sourceH) return hasVideoFrame;

  if (videoSourceWidth !== sourceW || videoSourceHeight !== sourceH) {
    videoSourceCanvas.width = sourceW;
    videoSourceCanvas.height = sourceH;
    videoSourceWidth = sourceW;
    videoSourceHeight = sourceH;
  }

  if (videoLayer.width !== width || videoLayer.height !== height) {
    videoLayer.resizeCanvas(width, height);
    videoLayer.pixelDensity(1);
    videoLayerCtx = videoLayer.drawingContext;
  }

  try {
    videoSourceCtx.drawImage(bgVideoEl, 0, 0, sourceW, sourceH);

    videoLayerCtx.save();
    videoLayerCtx.clearRect(0, 0, videoLayer.width, videoLayer.height);
    videoLayerCtx.drawImage(videoSourceCanvas, 0, 0, videoLayer.width, videoLayer.height);
    videoLayerCtx.restore();

    lastVideoTime = currentTime;
    hasVideoFrame = true;

    if (videoFadeStart === null) {
      videoFadeStart = millis();
      console.log("[video] first frame copied");
    }

    return true;
  } catch (err) {
    console.warn("[video] frame copy skipped:", err);
    return hasVideoFrame;
  }
}

function drawBackgroundFallback() {
  if (!bgPosterImg || !bgPosterImg.width || !bgPosterImg.height) return;
  image(bgPosterImg, 0, 0, width, height);
}

function getEmailHitRect() {
  const margin = 30;
  const x = width - margin;
  const y = margin;

  textSize(emailSize);
  const textW = textWidth(emailText);

  const padLeft = emailSize * 0.8;
  const padRight = emailSize * 0.2;
  const padY = emailSize * 0.25;

  return {
    left: x - textW - padLeft,
    right: x + padRight,
    top: y - padY,
    bottom: y + emailSize + padY,
    x,
    y
  };
}

function getSocialHitRects() {
  const size = emailSize * 0.8;
  const margin = 30;
  const spacing = size + 20;
  const xStart = margin;
  const y = margin;

  return socialLinks.map((item, i) => ({
    index: i,
    x: xStart + i * spacing,
    y,
    size,
    url: item.url
  }));
}

function pointInRect(px, py, rect) {
  return px >= rect.left && px <= rect.right && py >= rect.top && py <= rect.bottom;
}

function pointInBox(px, py, x, y, size) {
  return px >= x && px <= x + size && py >= y && py <= y + size;
}

function drawGlow(x, y, w, h, alpha) {
  push();
  noStroke();
  fill(glowColor[0], glowColor[1], glowColor[2], alpha * 0.6);
  drawingContext.filter = 'blur(12px)';
  rect(x, y, w, h, 6);
  pop();
}

function drawEmail() {
  const hit = getEmailHitRect();

  isHoveringEmail =
    mouseX >= hit.left &&
    mouseX <= hit.right &&
    mouseY >= hit.top &&
    mouseY <= hit.bottom;

  if (isHoveringEmail) {
    drawGlow(hit.left, hit.top, hit.right - hit.left, hit.bottom - hit.top, 255);
    cursor(HAND);
  } else {
    drawGlow(hit.left, hit.top, hit.right - hit.left, hit.bottom - hit.top, 0);
  }

  textSize(isHoveringEmail ? emailSize * 1.05 : emailSize);
  fill(255);
  textAlign(RIGHT, TOP);
  text(emailText, hit.x, hit.y);
}

function drawSocialIcons() {
  const size = emailSize * 0.8;
  const margin = 30;
  const spacing = size + 20;
  const xStart = margin;
  const y = margin;

  hoveringSocial = -1;

  const fadeProgress = constrain((millis() - fadeStartTime) / 1000, 0, 1);
  const alpha = fadeProgress * 255;

  socialLinks.forEach((item, i) => {
    const x = xStart + i * spacing;
    const icon = icons[item.imgKey];

    const isHover =
      mouseX > x &&
      mouseX < x + size &&
      mouseY > y &&
      mouseY < y + size;

    if (isHover) {
      hoveringSocial = i;
      cursor(HAND);
    }

    const glowAlpha = isHover ? 255 : 0;

    drawGlow(x - 6, y - 6, size + 12, size + 12, glowAlpha);

    if (icon && icon.width > 0 && icon.height > 0) {
      push();
      tint(255, alpha);
      image(icon, x, y, size, size);
      pop();
    }
  });
}

function drawDeploymentInfo() {
  if (!diag) return;

  const baseSize = min(windowWidth, windowHeight) * 0.02;
  textSize(baseSize);
  textAlign(LEFT);
  fill(255);

  const margin = 30;
  const x = margin;

  const lines = [
    `kubernetes: ${diag.kubernetes?.version ?? 'N/A'}`,
    `helm: ${diag.helm?.version ?? 'N/A'}`,
    `traefik: ${diag.traefik?.build?.version ?? 'N/A'}`,
    `pod ip: ${diag.pod?.ip ?? 'N/A'}`,
    `cluster ip: ${diag.awroberts?.service?.clusterIP ?? 'N/A'}`,
    `pod name: ${diag.pod?.name ?? 'N/A'}`,
    `awroberts sha: ${diag.awroberts?.build?.sha ?? 'N/A'}`,
    `background video sha: ${diag.backgroundVideo?.build?.sha ?? 'N/A'}`
  ];

  let y = height - margin - (baseSize * 1.3 * lines.length);

  for (let i = 0; i < lines.length; i++) {
    text(lines[i], x, y);
    y += baseSize * 1.3;
  }
}

function openEmail() {
  window.location.href = 'mailto:info@awroberts.co.uk';
}

function openSocial(index) {
  if (index < 0 || index >= socialLinks.length) return;
  window.open(socialLinks[index].url, '_blank', 'noopener,noreferrer');
}

function handlePointerActivation(px, py) {
  const emailHit = getEmailHitRect();
  if (pointInRect(px, py, emailHit)) {
    openEmail();
    return true;
  }

  const socialRects = getSocialHitRects();
  for (const rect of socialRects) {
    if (pointInBox(px, py, rect.x, rect.y, rect.size)) {
      openSocial(rect.index);
      return true;
    }
  }

  return false;
}

function mousePressed() {
  handlePointerActivation(mouseX, mouseY);
}

function touchStarted() {
  if (touches.length > 0) {
    handlePointerActivation(touches[0].x, touches[0].y);
  }
  return false;
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
  if (!bgVideoEl || !videoReady) return 0.35;
  if (!bgVideoEl.videoWidth || !bgVideoEl.videoHeight) return 0.35;

  const w = Math.min(96, bgVideoEl.videoWidth);
  const h = Math.min(96, bgVideoEl.videoHeight);

  if (videoSourceCanvas.width !== w || videoSourceCanvas.height !== h) {
    videoSourceCanvas.width = w;
    videoSourceCanvas.height = h;
  }

  try {
    videoSourceCtx.drawImage(bgVideoEl, 0, 0, w, h);
    const data = videoSourceCtx.getImageData(0, 0, w, h).data;

    let sumR = 0;
    let count = 0;

    for (let i = 0; i < data.length; i += 4) {
      sumR += data[i];
      count++;
    }

    return count ? (sumR / count) / 255 : 0.35;
  } catch (err) {
    console.warn('[video] Could not sample stream frame red channel:', err);
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

  if (videoLayer) {
    videoLayer.resizeCanvas(windowWidth, windowHeight);
    videoLayer.pixelDensity(1);
  }

  emailSize = constrain(min(windowWidth, windowHeight) * 0.05, 16, 70);
  textSize(emailSize);
}