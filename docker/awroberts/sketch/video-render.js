// video-render.js

// -----------------------------
// BROWSER ELEMENT INTERCEPTOR
// -----------------------------
// Patches the global browser prototype to catch p5.js during internal setup
// and forcefully inject the rendering hint before it draws a single pixel.
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
  videoSourceCtx = videoSourceCanvas.getContext("2d", { alpha: false });
  videoSourceReady = true;

  videoLayer = p5Instance.createGraphics(p5Instance.windowWidth, p5Instance.windowHeight);
  videoLayer.pixelDensity(1);
  videoLayer.clear();
  videoLayerReady = true;

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

  // PERFORMANCE OPTIMIZATION: Instead of allocating a massive 3840x2160 source canvas,
  // downscale the color sampling context layer structurally to a smart 1280x720 container.
  // This shields the main JS thread from heavy 4K pixel calculations during color readings.
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
    // Draw the high-fidelity 4K video input downscaled into our 720p sampling canvas buffer
    videoSourceCtx.drawImage(bgVideoEl, 0, 0, sampleW, sampleH);

    const destW = videoLayer.width;
    const destH = videoLayer.height;

    // Scale back up inside the graphics container to maintain clean visual sharpness on screen
    videoLayerCtx.save();
    videoLayerCtx.clearRect(0, 0, destW, destH);
    videoLayerCtx.drawImage(videoSourceCanvas, 0, 0, sampleW, sampleH, 0, 0, destW, destH);
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
