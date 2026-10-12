// video-render.js
import { bgVideoEl, videoReady, bgPosterImg, awrWeb } from './video-hls.js';

// -----------------------------
// RENDER ENGINE ARCHITECTURE STATE
// -----------------------------
let videoFadeStart = null;
const videoFadeDuration = 1200;

let videoSourceCanvas = null;
let videoSourceCtx = null;
let videoSourceReady = false;
let videoSourceWidth = 0;
let videoSourceHeight = 0;

let videoLayer = null;
let videoLayerCtx = null;
let videoLayerReady = false;

let lastVideoTime = -1;
let hasVideoFrame = false;

// -----------------------------
// CODESPACE INITIALIZATION PIPELINE
// -----------------------------
export function initRenderLayers(p5Instance) {
  videoSourceCanvas = document.createElement("canvas");
  videoSourceCtx = videoSourceCanvas.getContext("2d", { alpha: false, willReadFrequently: true });
  videoSourceReady = true;

  videoLayer = p5Instance.createGraphics(p5Instance.windowWidth, p5Instance.windowHeight);
  videoLayer.pixelDensity(1);
  videoLayer.clear();
  videoLayerReady = true;

  // Protect internal p5 properties by configuring the hint on the raw canvas reference directly
  videoLayer.canvas.getContext('2d', { willReadFrequently: true });
  videoLayerCtx = videoLayer.drawingContext;
}

// -----------------------------
// FRAME COPY LOGIC
// -----------------------------
export function getVideoLayerCanvas() {
  return (videoLayerReady && videoLayerCtx) ? videoLayerCtx.canvas : null;
}

export function getVideoFadeAlpha() {
  if (!hasVideoFrame || videoFadeStart === null) return 0;
  const t = (awrWeb.millis() - videoFadeStart) / videoFadeDuration;
  return Math.min(Math.max(t, 0), 1);
}

export function updateVideoFrame() {
  if (!bgVideoEl || !videoReady || !videoSourceReady || !videoLayerReady) return false;
  if (!bgVideoEl.videoWidth || !bgVideoEl.videoHeight) return false;

  const currentTime = bgVideoEl.currentTime;
  const hasAdvanced = currentTime !== lastVideoTime;

  if (hasVideoFrame && !hasAdvanced) return true;

  const sourceW = bgVideoEl.videoWidth;
  const sourceH = bgVideoEl.videoHeight;

  if (videoSourceWidth !== sourceW || videoSourceHeight !== sourceH) {
    videoSourceCanvas.width = sourceW;
    videoSourceCanvas.height = sourceH;
    videoSourceWidth = sourceW;
    videoSourceHeight = sourceH;
  }

  if (videoLayer.width !== awrWeb.width || videoLayer.height !== awrWeb.height) {
    videoLayer.resizeCanvas(awrWeb.width, awrWeb.height);
    videoLayer.pixelDensity(1);

    // Maintain rendering speed enhancements through structural frame resizes
    videoLayer.canvas.getContext('2d', { willReadFrequently: true });
    videoLayerCtx = videoLayer.drawingContext;
  }

  try {
    videoSourceCtx.drawImage(bgVideoEl, 0, 0, sourceW, sourceH);

    const destW = videoLayer.width;
    const destH = videoLayer.height;
    const srcAspect  = sourceW / sourceH;
    const destAspect = destW   / destH;

    let sx, sy, sw, sh;
    if (srcAspect > destAspect) {
      sh = sourceH;
      sw = sourceH * destAspect;
      sx = (sourceW - sw) / 2;
      sy = 0;
    } else {
      sw = sourceW;
      sh = sourceW / destAspect;
      sx = 0;
      sy = (sourceH - sh) / 2;
    }

    videoLayerCtx.save();
    videoLayerCtx.clearRect(0, 0, destW, destH);
    videoLayerCtx.drawImage(videoSourceCanvas, sx, sy, sw, sh, 0, 0, destW, destH);
    videoLayerCtx.restore();

    lastVideoTime = currentTime;
    hasVideoFrame = true;

    if (videoFadeStart === null) {
      videoFadeStart = awrWeb.millis();
      console.log("Video fade started");
    }

    return true;
  } catch (err) {
    console.warn("Video frame copy skipped:", err);
    return hasVideoFrame;
  }
}

// -----------------------------
// COLOUR SAMPLER
// -----------------------------
export function sampleVideoColumn(x) {
  if (!videoLayerReady || !hasVideoFrame) return null;
  try {
    const px = Math.floor(awrWeb.constrain(x, 0, videoLayer.width - 1));
    return videoLayerCtx.getImageData(px, 0, 1, videoLayer.height).data;
  } catch {
    return null;
  }
}

export function sampleVideoColor(x, y) {
  if (!videoLayerReady || !hasVideoFrame) return;
  try {
    const px = Math.floor(awrWeb.constrain(x, 0, videoLayer.width - 1));
    const py = Math.floor(awrWeb.constrain(y, 0, videoLayer.height - 1));
    const d = videoLayerCtx.getImageData(px, py, 1, 1).data;
    return [d[0], d[1], d[2]];
  } catch {
    return;
  }
}

// -----------------------------
// DRAW PIPELINE
// -----------------------------
export function drawBackgroundFallback() {
  if (!bgPosterImg) return;
  awrWeb.image(bgPosterImg, 0, 0, awrWeb.width, awrWeb.height);
}

export function drawVideo() {
  drawBackgroundFallback();

  if (!videoReady || !videoLayerReady) return;

  const frameAvailable = updateVideoFrame();
  if (!frameAvailable || !hasVideoFrame) return;

  let alpha = 255;
  if (videoFadeStart !== null) {
    const t = (awrWeb.millis() - videoFadeStart) / videoFadeDuration;
    alpha = awrWeb.constrain(t * 255, 0, 255);
  }

  awrWeb.push();
  awrWeb.drawingContext.globalAlpha = alpha / 255;
  awrWeb.image(videoLayer, 0, 0, awrWeb.width, awrWeb.height);
  awrWeb.pop();
}
