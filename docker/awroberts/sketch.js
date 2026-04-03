let bgVideoEl;
let hlsInstance = null;
let videoReady = false;
let videoFadeStart = null;
let videoFadeDuration = 1200;

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

// Retro-digital effect buffers
let retroBaseLayer = null;
let retroBaseCtx = null;
let retroBaseReady = false;

let retroFocusLayer = null;
let retroFocusCtx = null;
let retroFocusReady = false;

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

const glowColor = [127, 203, 255];

// Cache-buster to force fresh HLS session
const VIDEO_URL = "https://awroberts.co.uk/stream/index.m3u8?v=" + Date.now();

// Retro digital tuning
const RETRO = {
  basePixelSize: 10,
  hoverPixelSize: 22,
  focusRadius: 220,
  posterizeLevels: 6,
  scanlineSpacing: 3,
  scanlineAlpha: 18,
  jitterMax: 2,
  rgbSplitMax: 2,
  sharpenStrength: 0.95
};

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

  retroBaseLayer = createGraphics(windowWidth, windowHeight);
  retroBaseLayer.pixelDensity(1);
  retroBaseLayer.clear();
  retroBaseReady = true;
  retroBaseCtx = retroBaseLayer.drawingContext;

  retroFocusLayer = createGraphics(windowWidth, windowHeight);
  retroFocusLayer.pixelDensity(1);
  retroFocusLayer.clear();
  retroFocusReady = true;
  retroFocusCtx = retroFocusLayer.drawingContext;

  bgVideoEl = document.getElementById("bg-video");

  if (bgVideoEl) {
    bgVideoEl.loop = false;
    bgVideoEl.playsInline = true;
    bgVideoEl.muted = true;

    bgVideoEl.addEventListener("ended", () => {
      console.log("Video ended; restarting VOD loop");
      bgVideoEl.currentTime = 0;
      bgVideoEl.play().catch(err => console.warn("play() failed:", err));
    });

    if ("requestVideoFrameCallback" in bgVideoEl) {
      const onFirstFrame = () => {
        console.log("First decoded frame detected");
        videoReady = true;
        if (videoFadeStart === null) {
          videoFadeStart = millis();
        }
      };
      bgVideoEl.requestVideoFrameCallback(onFirstFrame);
    } else {
      bgVideoEl.addEventListener("canplay", () => {
        console.log("Video canplay fired");
        videoReady = true;
        if (videoFadeStart === null) {
          videoFadeStart = millis();
        }
      });
    }
  }

  if (bgVideoEl) {
    if (Hls.isSupported()) {
      hlsInstance = new Hls({
        enableWorker: true,
        lowLatencyMode: false,
        maxBufferLength: 60,
        maxBufferSize: 120 * 1000 * 1000,
        maxMaxBufferLength: 120,
        backBufferLength: 0,
        startPosition: 0
      });

      hlsInstance.on(Hls.Events.ERROR, (event, data) => {
        console.warn("HLS.js error:", data);

        if (data.fatal) {
          if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
            hlsInstance.recoverMediaError();
          } else if (data.type === Hls.ErrorTypes.NETWORK_ERROR) {
            hlsInstance.startLoad();
          } else {
            hlsInstance.destroy();
          }
        }
      });

      hlsInstance.on(Hls.Events.MEDIA_ATTACHED, () => {
        console.log("HLS.js media attached");
        bgVideoEl.play().catch(err => console.warn("play() failed:", err));
      });

      hlsInstance.on(Hls.Events.MANIFEST_PARSED, () => {
        console.log("HLS.js manifest parsed");
        bgVideoEl.play().catch(err => console.warn("play() failed:", err));
      });

      console.log("Loading HLS source:", VIDEO_URL);
      hlsInstance.loadSource(VIDEO_URL);
      hlsInstance.attachMedia(bgVideoEl);
    } else if (bgVideoEl.canPlayType("application/vnd.apple.mpegurl")) {
      console.log("Native HLS supported");
      bgVideoEl.src = VIDEO_URL;
      bgVideoEl.play().catch(err => console.warn("play() failed:", err));
    }
  }

  emailSize = constrain(min(windowWidth, windowHeight) * 0.05, 16, 70);

  textFont(curwenFont);
  textSize(emailSize);
  textAlign(RIGHT, TOP);

  fadeStartTime = millis();
}

// ---------------------------------------------------
// Frame capture + retro-digital processing
// ---------------------------------------------------
function ensureLayerSize(layer) {
  if (layer.width !== width || layer.height !== height) {
    layer.resizeCanvas(width, height);
    layer.pixelDensity(1);
  }
}

function copyVideoToBaseLayer() {
  if (!bgVideoEl) return false;
  if (!videoReady) return false;
  if (!videoSourceReady || !retroBaseReady) return false;
  if (!bgVideoEl.videoWidth || !bgVideoEl.videoHeight) return false;

  const sourceW = bgVideoEl.videoWidth;
  const sourceH = bgVideoEl.videoHeight;

  if (!sourceW || !sourceH) return false;

  if (videoSourceWidth !== sourceW || videoSourceHeight !== sourceH) {
    videoSourceCanvas.width = sourceW;
    videoSourceCanvas.height = sourceH;
    videoSourceWidth = sourceW;
    videoSourceHeight = sourceH;
  }

  ensureLayerSize(retroBaseLayer);

  try {
    videoSourceCtx.drawImage(bgVideoEl, 0, 0, sourceW, sourceH);

    const basePixelSize = mouseIsPressed || isHoveringAnyInteractive() ? RETRO.hoverPixelSize : RETRO.basePixelSize;
    renderRetroPixelatedFrame(videoSourceCanvas, retroBaseCtx, width, height, basePixelSize, RETRO.posterizeLevels);

    lastVideoTime = bgVideoEl.currentTime;
    hasVideoFrame = true;
    return true;
  } catch (err) {
    console.warn("Video frame copy skipped:", err);
    return hasVideoFrame;
  }
}

function isHoveringAnyInteractive() {
  return isHoveringEmail || hoveringSocial >= 0;
}

function renderRetroPixelatedFrame(sourceCanvas, targetCtx, targetW, targetH, pixelSize, posterizeLevels) {
  if (!sourceCanvas || !targetCtx) return;

  targetCtx.save();
  targetCtx.imageSmoothingEnabled = false;
  targetCtx.clearRect(0, 0, targetW, targetH);

  const sampleW = Math.max(1, Math.floor(targetW / pixelSize));
  const sampleH = Math.max(1, Math.floor(targetH / pixelSize));

  const lowRes = document.createElement("canvas");
  lowRes.width = sampleW;
  lowRes.height = sampleH;
  const lowCtx = lowRes.getContext("2d", { alpha: false });
  lowCtx.imageSmoothingEnabled = true;
  lowCtx.drawImage(sourceCanvas, 0, 0, sampleW, sampleH);

  const img = lowCtx.getImageData(0, 0, sampleW, sampleH);
  const d = img.data;

  for (let i = 0; i < d.length; i += 4) {
    d[i] = posterize(d[i], posterizeLevels);
    d[i + 1] = posterize(d[i + 1], posterizeLevels);
    d[i + 2] = posterize(d[i + 2], posterizeLevels);
  }

  lowCtx.putImageData(img, 0, 0);

  targetCtx.drawImage(lowRes, 0, 0, targetW, targetH);
  targetCtx.restore();
}

function posterize(v, levels) {
  const step = 255 / Math.max(2, levels - 1);
  return Math.round(v / step) * step;
}

function applySharpenToCanvas(graphics, strength) {
  if (!graphics || strength <= 0) return;

  const ctx = graphics.drawingContext;
  const w = graphics.width;
  const h = graphics.height;

  const src = ctx.getImageData(0, 0, w, h);
  const dst = ctx.createImageData(w, h);

  const s = constrain(strength, 0, 1.5);
  const kernel = [
    0, -1 * s, 0,
    -1 * s, 1 + 4 * s, -1 * s,
    0, -1 * s, 0
  ];

  const data = src.data;
  const out = dst.data;

  const getIndex = (x, y) => (y * w + x) * 4;

  for (let y = 1; y < h - 1; y++) {
    for (let x = 1; x < w - 1; x++) {
      let r = 0, g = 0, b = 0;

      const positions = [
        [x - 1, y - 1], [x, y - 1], [x + 1, y - 1],
        [x - 1, y],     [x, y],     [x + 1, y],
        [x - 1, y + 1], [x, y + 1], [x + 1, y + 1]
      ];

      for (let k = 0; k < 9; k++) {
        const idx = getIndex(positions[k][0], positions[k][1]);
        const wgt = kernel[k];
        r += data[idx] * wgt;
        g += data[idx + 1] * wgt;
        b += data[idx + 2] * wgt;
      }

      const i = getIndex(x, y);
      out[i] = constrain(r, 0, 255);
      out[i + 1] = constrain(g, 0, 255);
      out[i + 2] = constrain(b, 0, 255);
      out[i + 3] = data[i + 3];
    }
  }

  ctx.putImageData(dst, 0, 0);
}

function drawScanlines(targetGraphics, alpha = RETRO.scanlineAlpha) {
  targetGraphics.push();
  targetGraphics.noStroke();
  targetGraphics.fill(0, 0, 0, alpha);
  for (let y = 0; y < targetGraphics.height; y += RETRO.scanlineSpacing) {
    targetGraphics.rect(0, y, targetGraphics.width, 1);
  }
  targetGraphics.pop();
}

function drawVignette(targetGraphics) {
  targetGraphics.push();
  targetGraphics.noFill();
  for (let i = 0; i < 6; i++) {
    const a = 18 - i * 2;
    targetGraphics.stroke(0, 0, 0, a);
    targetGraphics.strokeWeight(40);
    targetGraphics.rect(
      i * 14,
      i * 14,
      targetGraphics.width - i * 28,
      targetGraphics.height - i * 28,
      18
    );
  }
  targetGraphics.pop();
}

function drawRGBSplit(sourceGraphics) {
  const jitter = isHoveringAnyInteractive() ? RETRO.rgbSplitMax : 1;
  push();
  blendMode(SCREEN);
  tint(255, 120, 120, 70);
  image(sourceGraphics, jitter, 0, width, height);
  tint(120, 255, 120, 50);
  image(sourceGraphics, -jitter, 0, width, height);
  tint(120, 120, 255, 50);
  image(sourceGraphics, 0, jitter, width, height);
  pop();
}

function drawFocusSharpenOverlay() {
  if (!mouseX && !mouseY) return;

  const d = dist(mouseX, mouseY, width / 2, height / 2);
  const hoverBoost = isHoveringAnyInteractive() ? 1 : 0;
  const focusRadius = RETRO.focusRadius + (hoverBoost * 80);

  if (d > focusRadius) return;

  const t = 1 - constrain(d / focusRadius, 0, 1);
  const alpha = 70 * t;
  const size = map(t, 0, 1, RETRO.hoverPixelSize, 6);

  if (!retroFocusReady) return;
  ensureLayerSize(retroFocusLayer);

  retroFocusCtx.save();
  retroFocusCtx.clearRect(0, 0, retroFocusLayer.width, retroFocusLayer.height);
  retroFocusCtx.imageSmoothingEnabled = true;
  retroFocusCtx.drawImage(retroBaseLayer.elt, 0, 0, width, height);

  const regionSize = Math.max(90, Math.floor(220 * t));
  const sx = constrain(mouseX - regionSize / 2, 0, width - regionSize);
  const sy = constrain(mouseY - regionSize / 2, 0, height - regionSize);
  const sw = regionSize;
  const sh = regionSize;

  const temp = document.createElement("canvas");
  temp.width = sw;
  temp.height = sh;
  const tctx = temp.getContext("2d", { alpha: false });
  tctx.imageSmoothingEnabled = false;
  tctx.drawImage(retroBaseLayer.elt, sx, sy, sw, sh, 0, 0, sw, sh);

  const img = tctx.getImageData(0, 0, sw, sh);
  const dta = img.data;
  for (let i = 0; i < dta.length; i += 4) {
    dta[i] = posterize(dta[i], 8);
    dta[i + 1] = posterize(dta[i + 1], 8);
    dta[i + 2] = posterize(dta[i + 2], 8);
  }
  tctx.putImageData(img, 0, 0);

  retroFocusCtx.image(temp, sx, sy, sw, sh);
  retroFocusCtx.restore();

  push();
  tint(255, 255, 255, 255);
  image(retroFocusLayer, 0, 0, width, height);
  pop();

  drawGlow(mouseX - 20, mouseY - 20, 40, 40, alpha);
  drawingContext.filter = 'blur(0px)';
}

function draw() {
  clear();

  if (videoReady && retroBaseReady) {
    const frameAvailable = copyVideoToBaseLayer();

    if (frameAvailable || hasVideoFrame) {
      const shouldJitter = frameCount % 9 === 0 && !isHoveringAnyInteractive();
      const jx = shouldJitter ? random(-RETRO.jitterMax, RETRO.jitterMax) : 0;
      const jy = shouldJitter ? random(-RETRO.jitterMax, RETRO.jitterMax) : 0;

      let alpha = 255;
      if (videoFadeStart !== null) {
        const t = (millis() - videoFadeStart) / videoFadeDuration;
        alpha = constrain(t * 255, 0, 255);
      }

      push();
      translate(jx, jy);
      tint(255, alpha);
      image(retroBaseLayer, 0, 0, width, height);
      pop();

      drawRGBSplit(retroBaseLayer);
      drawScanlines(this, RETRO.scanlineAlpha);
      drawVignette(this);

      if (isHoveringAnyInteractive()) {
        applySharpenToCanvas(retroBaseLayer, RETRO.sharpenStrength * 0.6);
      }

      drawFocusSharpenOverlay();
    }
  }

  drawEmail();
  drawSocialIcons();
  drawDeploymentInfo();
}

// ----------------------------
// Shared hit testing
// ----------------------------
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
  return (
    px >= rect.left &&
    px <= rect.right &&
    py >= rect.top &&
    py <= rect.bottom
  );
}

function pointInBox(px, py, x, y, size) {
  return (
    px >= x &&
    px <= x + size &&
    py >= y &&
    py <= y + size
  );
}

// ----------------------------
// GLOW HELPER
// ----------------------------
function drawGlow(x, y, w, h, alpha) {
  push();
  noStroke();
  fill(glowColor[0], glowColor[1], glowColor[2], alpha * 0.6);
  drawingContext.filter = 'blur(12px)';
  rect(x, y, w, h, 6);
  drawingContext.filter = 'none';
  pop();
}

// ----------------------------
// EMAIL
// ----------------------------
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

// ----------------------------
// SOCIAL ICONS
// ----------------------------
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

// ----------------------------
// DEPLOYMENT INFO
// ----------------------------
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
    `pod name: ${diag.pod?.name ?? 'N/A'}`,
    `pod ip: ${diag.pod?.ip ?? 'N/A'}`,
    `cluster ip: ${diag.awroberts?.service?.clusterIP ?? 'N/A'}`,
    `awroberts sha: ${diag.awroberts?.build?.sha ?? 'N/A'}`,
    `background video sha: ${diag.backgroundVideo?.build?.sha ?? 'N/A'}`
  ];

  let y = height - margin - (baseSize * 1.3 * lines.length);

  for (let i = 0; i < lines.length; i++) {
    text(lines[i], x, y);
    y += baseSize * 1.3;
  }
}

// ----------------------------
// INTERACTION
// ----------------------------
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

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);

  if (videoLayer) {
    videoLayer.resizeCanvas(windowWidth, windowHeight);
    videoLayer.pixelDensity(1);
  }

  if (retroBaseLayer) {
    retroBaseLayer.resizeCanvas(windowWidth, windowHeight);
    retroBaseLayer.pixelDensity(1);
  }

  if (retroFocusLayer) {
    retroFocusLayer.resizeCanvas(windowWidth, windowHeight);
    retroFocusLayer.pixelDensity(1);
  }

  emailSize = constrain(min(windowWidth, windowHeight) * 0.05, 16, 70);
  textSize(emailSize);
}