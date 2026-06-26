// video.js

// -----------------------------
// INTERNAL P5 INSTANCE
// -----------------------------
let awrWeb = null;

export function bindVideoP5(p) {
  awrWeb = p;
}

// -----------------------------
// VIDEO STATE
// -----------------------------
export let bgVideoEl;
let hlsInstance = null;
let videoReady = false;

let videoFadeStart = null;
const videoFadeDuration = 1200;

let bgPosterImg = null;

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

let watchdogFrozenSince = null;

const HlsGlobal = window.Hls;

const VIDEO_URL = "https://awroberts.co.uk/stream/index.m3u8?v=" + Date.now();
const POSTER_URL = "/background-poster.png";

// -----------------------------
// PRELOAD
// -----------------------------
export function preloadVideoAssets() {
  bgPosterImg = awrWeb.loadImage(POSTER_URL + '?v=' + Date.now());
}

// -----------------------------
// INIT (with DOM-ready + retry)
// -----------------------------
export function initVideoSystem() {
  console.log("initVideoSystem() called");

  // Ensure DOM is ready
  if (document.readyState !== "complete" && document.readyState !== "interactive") {
    console.log("DOM not ready — retrying initVideoSystem()");
    return setTimeout(initVideoSystem, 50);
  }

  bgVideoEl = document.getElementById("bg-video");

  if (!bgVideoEl) {
    console.warn("bgVideoEl not found — retrying initVideoSystem()");
    return setTimeout(initVideoSystem, 50);
  }

  console.log("initVideoSystem(): video element found:", bgVideoEl);

  // Offscreen canvas for raw video frame
  videoSourceCanvas = document.createElement("canvas");
  videoSourceCtx = videoSourceCanvas.getContext("2d", { alpha: false, willReadFrequently: true });
  videoSourceReady = true;

  // p5 graphics layer for scaled output
  videoLayer = awrWeb.createGraphics(awrWeb.windowWidth, awrWeb.windowHeight);
  videoLayer.pixelDensity(1);
  videoLayer.clear();
  videoLayerReady = true;
  videoLayerCtx = videoLayer.drawingContext;

  setupVideoEvents();
  setupHLS();

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState !== "visible" || !bgVideoEl) return;
    console.log("Tab visible — seeking to live edge");
    if (hlsInstance) {
      hlsInstance.startLoad(-1);
      const livePos = hlsInstance.liveSyncPosition;
      if (livePos != null && isFinite(livePos)) {
        bgVideoEl.currentTime = livePos;
      }
    } else {
      // Native HLS (Safari)
      const seekable = bgVideoEl.seekable;
      if (seekable && seekable.length > 0) {
        bgVideoEl.currentTime = seekable.end(seekable.length - 1);
      }
    }
    if (bgVideoEl.paused) {
      bgVideoEl.play().catch(err => console.warn("play() after visibility:", err));
    }
  });

  setInterval(() => {
    if (!videoReady) {
      bgPosterImg = awrWeb.loadImage(POSTER_URL + '?v=' + Date.now());
    }
  }, 4000);

  // Watchdog: restart HLS if currentTime hasn't advanced for 5s while not paused
  let watchdogLastTime = -1;
  setInterval(() => {
    if (!bgVideoEl || !videoReady) return;
    if (bgVideoEl.ended) {
      console.warn("Video watchdog: ended state, reinitialising HLS");
      watchdogFrozenSince = null;
      if (hlsInstance) { hlsInstance.destroy(); hlsInstance = null; }
      videoReady = false;
      setupHLS();
      return;
    }
    if (bgVideoEl.paused) { watchdogFrozenSince = null; watchdogLastTime = bgVideoEl.currentTime; return; }

    const ct = bgVideoEl.currentTime;
    if (ct === watchdogLastTime) {
      if (watchdogFrozenSince === null) {
        watchdogFrozenSince = Date.now();
      } else if (Date.now() - watchdogFrozenSince > 5000) {
        console.warn("Video watchdog: frozen, restarting HLS");
        watchdogFrozenSince = null;
        if (hlsInstance) {
          hlsInstance.stopLoad();
          hlsInstance.startLoad(-1);
        }
        bgVideoEl.play().catch(err => console.warn("Watchdog play() failed:", err));
      }
    } else {
      watchdogFrozenSince = null;
      watchdogLastTime = ct;
    }
  }, 1000);
}

// -----------------------------
// VIDEO EVENTS
// -----------------------------
function setupVideoEvents() {
  bgVideoEl.loop = false;

  bgVideoEl.addEventListener("ended", () => {
    console.warn("Video ended — reinitialising HLS");
    if (hlsInstance) {
      hlsInstance.destroy();
      hlsInstance = null;
    }
    videoReady = false;
    setupHLS();
  });

  bgVideoEl.addEventListener("stalled", () => {
    console.warn("Video event: stalled — paused=" + bgVideoEl.paused + " ended=" + bgVideoEl.ended + " t=" + bgVideoEl.currentTime.toFixed(2));
  });

  bgVideoEl.addEventListener("waiting", () => {
    console.warn("Video event: waiting — paused=" + bgVideoEl.paused + " ended=" + bgVideoEl.ended + " t=" + bgVideoEl.currentTime.toFixed(2));
  });

  bgVideoEl.addEventListener("pause", () => {
    console.warn("Video event: pause — ended=" + bgVideoEl.ended + " t=" + bgVideoEl.currentTime.toFixed(2));
  });

  const markVideoReady = () => {
    if (!videoReady) console.log("Video ready");
    videoReady = true;
  };

  if ("requestVideoFrameCallback" in bgVideoEl) {
    bgVideoEl.requestVideoFrameCallback(() => {
      console.log("First decoded frame detected");
      markVideoReady();
    });
  } else {
    bgVideoEl.addEventListener("canplay", markVideoReady);
    bgVideoEl.addEventListener("loadeddata", markVideoReady);
  }
}

// -----------------------------
// HLS INITIALISATION
// -----------------------------
function setupHLS() {
  console.log("setupHLS(): HlsGlobal =", HlsGlobal);

  if (HlsGlobal && HlsGlobal.isSupported()) {
    console.log("Using HLS.js");

    hlsInstance = new HlsGlobal({
      enableWorker: true,
      lowLatencyMode: false,
      maxBufferLength: 4,
      maxBufferSize: 10 * 1000 * 1000,
      maxMaxBufferLength: 8,
      backBufferLength: 0,
      startPosition: -1,
      liveSyncDurationCount: 2,
      liveMaxLatencyDurationCount: 4
    });

    hlsInstance.on(HlsGlobal.Events.ERROR, (event, data) => {
      console.warn(`HLS.js error [fatal=${data.fatal}] type=${data.type} details=${data.details}`, data);

      if (!data.fatal && data.details === HlsGlobal.ErrorDetails.BUFFER_STALLED_ERROR) {
        console.warn("HLS.js buffer stalled — nudging load");
        hlsInstance.startLoad(-1);
        return;
      }

      if (data.fatal) {
        if (data.type === HlsGlobal.ErrorTypes.MEDIA_ERROR) {
          console.warn("HLS.js fatal media error — recovering");
          hlsInstance.recoverMediaError();
        } else if (data.type === HlsGlobal.ErrorTypes.NETWORK_ERROR) {
          console.warn("HLS.js fatal network error — restarting load");
          hlsInstance.startLoad(-1);
        } else {
          console.warn("HLS.js fatal other error — reinitialising");
          hlsInstance.destroy();
          hlsInstance = null;
          videoReady = false;
          setupHLS();
        }
      }
    });

    hlsInstance.on(HlsGlobal.Events.MEDIA_ATTACHED, () => {
      console.log("HLS.js media attached");
      bgVideoEl.play().catch(err => console.warn("play() failed:", err));
    });

    hlsInstance.on(HlsGlobal.Events.MANIFEST_PARSED, () => {
      console.log("HLS.js manifest parsed");
      bgVideoEl.play().catch(err => console.warn("play() failed:", err));
    });

    console.log("Loading HLS source:", VIDEO_URL);
    hlsInstance.loadSource(VIDEO_URL);
    hlsInstance.attachMedia(bgVideoEl);

  } else if (bgVideoEl.canPlayType("application/vnd.apple.mpegurl")) {
    console.log("Using native HLS");
    bgVideoEl.src = VIDEO_URL;
    bgVideoEl.play().catch(err => console.warn("play() failed:", err));
  } else {
    console.warn("No HLS support detected");
  }
}

// -----------------------------
// FRAME COPY
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
    videoLayerCtx = videoLayer.drawingContext;
  }

  try {
    videoSourceCtx.drawImage(bgVideoEl, 0, 0, sourceW, sourceH);

    // Cover crop: scale to fill canvas, cropping edges rather than squashing
    const destW = videoLayer.width;
    const destH = videoLayer.height;
    const srcAspect  = sourceW / sourceH;
    const destAspect = destW   / destH;

    let sx, sy, sw, sh;
    if (srcAspect > destAspect) {
      // Source wider than dest — crop sides, fill height
      sh = sourceH;
      sw = sourceH * destAspect;
      sx = (sourceW - sw) / 2;
      sy = 0;
    } else {
      // Source taller than dest — crop top/bottom, fill width
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

// Returns a full vertical column of pixel data as a Uint8ClampedArray
// (r,g,b,a per row) — one getImageData call for the whole height,
// far cheaper than calling sampleVideoColor once per scan line.
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
  if (!videoLayerReady || !hasVideoFrame) return [200, 200, 200];
  try {
    const px = Math.floor(awrWeb.constrain(x, 0, videoLayer.width - 1));
    const py = Math.floor(awrWeb.constrain(y, 0, videoLayer.height - 1));
    const d = videoLayerCtx.getImageData(px, py, 1, 1).data;
    return [d[0], d[1], d[2]];
  } catch {
    return [200, 200, 200];
  }
}

// -----------------------------
// DRAW
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
