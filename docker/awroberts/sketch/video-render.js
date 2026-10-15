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
// DUAL-BUFFER MEMORY TRACKING CHANNELS
// ----------------------------------------------------
let currentMobileImg = null;
let nextMobileImg = null;
let blendStartMillis = null;
const BLEND_DURATION = 2000; // FIXED: Stretches the cross-fade across the entire 2-second heartbeat

export function stageNextMobileFrame(freshImage) {
  if (!currentMobileImg) {
    currentMobileImg = freshImage;
    return;
  }
  nextMobileImg = freshImage;
  blendStartMillis = awrWeb.millis();
}

function drawCroppedImage(img, alpha) {
  if (!img) return;

  awrWeb.push();
  awrWeb.imageMode(awrWeb.CENTER);
  awrWeb.drawingContext.globalAlpha = alpha / 255;

  let imgW = img.width > 10 ? img.width : 3840;
  let imgH = img.height > 10 ? img.height : 2160;

  let scaleX = awrWeb.width / imgW;
  let scaleY = awrWeb.height / imgH;
  let dominantScale = Math.max(scaleX, scaleY);

  let renderWidth = imgW * dominantScale;
  let renderHeight = imgH * dominantScale;

  awrWeb.image(
    img,
    awrWeb.width / 2,
    awrWeb.height / 2,
    renderWidth,
    renderHeight
  );
  awrWeb.pop();
}

export function drawBackgroundFallback() {
  if (typeof isMobile !== 'undefined' && !isMobile) {
    if (bgPosterImg) {
      awrWeb.push();
      awrWeb.imageMode(awrWeb.CENTER);

      let currentAlpha = awrWeb.drawingContext.globalAlpha * 255;
      let safeAlpha = Math.max(100, currentAlpha);
      awrWeb.drawingContext.globalAlpha = safeAlpha / 255;

      let imgW = bgPosterImg.width > 10 ? bgPosterImg.width : 3840;
      let imgH = bgPosterImg.height > 10 ? bgPosterImg.height : 2160;

      let scaleX = awrWeb.width / imgW;
      let scaleY = awrWeb.height / imgH;
      let dominantScale = Math.max(scaleX, scaleY);

      let renderWidth = imgW * dominantScale;
      let renderHeight = imgH * dominantScale;

      awrWeb.image(
        bgPosterImg,
        awrWeb.width / 2,
        awrWeb.height / 2,
        renderWidth,
        renderHeight
      );
      awrWeb.pop();
    }
    return;
  }

  if (!currentMobileImg) {
    if (bgPosterImg) currentMobileImg = bgPosterImg;
    else return;
  }

  if (nextMobileImg && blendStartMillis !== null) {
    let elapsed = awrWeb.millis() - blendStartMillis;
    let progress = awrWeb.constrain(elapsed / BLEND_DURATION, 0, 1);

    // SINE INTERPOLATION CURVE: Smooth sinusoidal wave multiplier
    let sineProgress = (1 - Math.cos(progress * Math.PI)) / 2;

    let currentAlpha = awrWeb.constrain((1 - sineProgress) * 255, 0, 255);
    let nextAlpha = awrWeb.constrain(sineProgress * 255, 0, 255);

    drawCroppedImage(currentMobileImg, currentAlpha);
    drawCroppedImage(nextMobileImg, nextAlpha);

    if (progress >= 1) {
      currentMobileImg = nextMobileImg;
      nextMobileImg = null;
      blendStartMillis = null;
    }
  } else {
    drawCroppedImage(currentMobileImg, 255);
  }
}

export function drawVideo() {
  drawBackgroundFallback();

  if (typeof isMobile !== 'undefined' && isMobile) return;
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
  awrWeb.imageMode(awrWeb.CENTER);

  let vidW = videoLayer.width > 10 ? videoLayer.width : 3840;
  let vidH = videoLayer.height > 10 ? videoLayer.height : 2160;

  let scaleX = awrWeb.width / vidW;
  let scaleY = awrWeb.height / vidH;
  let dominantScale = Math.max(scaleX, scaleY);

  let renderWidth = vidW * dominantScale;
  let renderHeight = vidH * dominantScale;

  awrWeb.image(
    videoLayer,
    awrWeb.width / 2,
    awrWeb.height / 2,
    renderWidth,
    renderHeight
  );

  awrWeb.pop();
}
