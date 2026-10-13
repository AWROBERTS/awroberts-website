// video-render.js

// ----------------------------------------------------
// PATHTYPE INTERCEPTOR (Silences readback warnings)
// ----------------------------------------------------
(function() {
  const originalGetContext = HTMLCanvasElement.prototype.getContext;
  HTMLCanvasElement.prototype.getContext = function(type, attributes) {
    if (type === '2d') {
      attributes = attributes || {};
      attributes.willReadFrequently = true;
    }
    return originalGetContext.call(this, type, attributes);
  };
})();

import { bgVideoEl, videoReady, bgPosterImg, awrWeb } from './video-hls.js';

// ----------------------------------------------------
// RENDER ENGINE ARCHITECTURE STATE
// ----------------------------------------------------
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

// ----------------------------------------------------
// CODESPACE INITIALIZATION PIPELINE
// ----------------------------------------------------
export function initRenderLayers(p5Instance) {
  videoSourceCanvas = document.createElement("canvas");
  videoSourceCtx = videoSourceCanvas.getContext("2d", { alpha: false });
  videoSourceReady = true;

  videoLayer = p5Instance.createGraphics(p5Instance.windowWidth, p5Instance.windowHeight);
  videoLayer.pixelDensity(1);
  videoLayer.clear();
  videoLayerReady = true;
  videoLayerCtx = videoLayer.drawingContext;
}

// ----------------------------------------------------
// GETTERS & ACCELERATORS
// ----------------------------------------------------
export function getVideoLayerCanvas() {
  return (videoLayerReady && videoLayerCtx) ? videoLayerCtx.canvas : null;
}

export function getVideoFadeAlpha() {
  if (!hasVideoFrame || videoFadeStart === null) return 0;
  const t = (awrWeb.millis() - videoFadeStart) / videoFadeDuration;
  return Math.min(Math.max(t, 0), 1);
}

// ----------------------------------------------------
// CORE FRAME RENDERING PIPELINE
// ----------------------------------------------------
export function updateVideoFrame() {
  if (!bgVideoEl || !videoReady || !videoSourceReady || !videoLayerReady) return false;
  if (!bgVideoEl.videoWidth || !bgVideoEl.videoHeight) return false;

  const currentTime = bgVideoEl.currentTime;
  const hasAdvanced = currentTime !== lastVideoTime;

  if (hasVideoFrame && !hasAdvanced) return true;

  // Set a clean 720p internal sampling size boundary to limit main thread strain
  const sampleW = 1280;
  const sampleH = 720;

  if (videoSourceWidth !== sampleW || videoSourceHeight !== sampleH) {
    videoSourceCanvas.width = sampleW;
    videoSourceCanvas.height = sampleH;
    videoSourceWidth = sampleW;
    videoSourceHeight = sampleH;
  }

  if (videoLayer.width !== awrWeb.width || videoLayer.height !== awrWeb.height) {
    videoLayer.resizeCanvas(awrWeb.width, awrWeb.height);
    videoLayer.pixelDensity(1);
    videoLayerCtx = videoLayer.drawingContext;
  }

  try {
    // 1. Draw raw high-fidelity 4K frame downscaled into our 720p memory buffer canvas
    videoSourceCtx.drawImage(bgVideoEl, 0, 0, sampleW, sampleH);

    const destW = videoLayer.width;
    const destH = videoLayer.height;

    // 2. Draw scaled back up on the visual canvas layer to maintain crystal clear screen sharpness
    videoLayerCtx.save();
    videoLayerCtx.clearRect(0, 0, destW, destH);
    videoLayerCtx.drawImage(videoSourceCanvas, 0, 0, sampleW, sampleH, 0, 0, destW, destH);
    videoLayerCtx.restore();

    lastVideoTime = currentTime;
    hasVideoFrame = true;

    if (videoFadeStart === null) {
      videoFadeStart = awrWeb.millis();
    }

    return true;
  } catch (err) {
    return hasVideoFrame;
  }
}

// ----------------------------------------------------
// HIGH-PERFORMANCE PIXEL COLOUR SAMPLERS
// ----------------------------------------------------
export function sampleVideoColumn(x) {
  if (!videoSourceReady || !hasVideoFrame) return null;
  try {
    // Map the full-viewport X position down to the matching relative coordinate in our 720p canvas
    const scaleX = (x / awrWeb.width) * videoSourceWidth;
    const px = Math.floor(Math.max(0, Math.min(scaleX, videoSourceWidth - 1)));

    // CRUCIAL FIX: Samples from videoSourceCtx (720px tall) instead of reading full screen context height.
    return videoSourceCtx.getImageData(px, 0, 1, videoSourceHeight).data;
  } catch (err) {
    return null;
  }
}

export function sampleVideoColor(x, y) {
  if (!videoSourceReady || !hasVideoFrame) return null;
  try {
    const scaleX = (x / awrWeb.width) * videoSourceWidth;
    const scaleY = (y / awrWeb.height) * videoSourceHeight;
    const px = Math.floor(Math.max(0, Math.min(scaleX, videoSourceWidth - 1)));
    const py = Math.floor(Math.max(0, Math.min(scaleY, videoSourceHeight - 1)));

    const d = videoSourceCtx.getImageData(px, py, 1, 1).data;
    return [d, d, d];
  } catch (err) {
    return null;
  }
}

// ----------------------------------------------------
// STAGE BACKGROUND DRAW LOOP INTERFACES
// ----------------------------------------------------
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
