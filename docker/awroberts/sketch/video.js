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

const HlsGlobal = window.Hls;

const VIDEO_URL = "https://awroberts.co.uk/stream/index.m3u8?v=" + Date.now();
const POSTER_URL = "/awroberts-media/background-poster.png";

// -----------------------------
// PRELOAD
// -----------------------------
export function preloadVideoAssets() {
  bgPosterImg = awrWeb.loadImage(POSTER_URL);
}

// -----------------------------
// INIT
// -----------------------------
export function initVideoSystem() {
  bgVideoEl = document.getElementById("bg-video");

  console.log("initVideoSystem():", { bgVideoEl, HlsGlobal });

  // Offscreen canvas for raw video frame
  videoSourceCanvas = document.createElement("canvas");
  videoSourceCtx = videoSourceCanvas.getContext("2d", { alpha: false });
  videoSourceReady = true;

  // p5 graphics layer for scaled output
  videoLayer = awrWeb.createGraphics(awrWeb.windowWidth, awrWeb.windowHeight);
  videoLayer.pixelDensity(1);
  videoLayer.clear();
  videoLayerReady = true;
  videoLayerCtx = videoLayer.drawingContext;

  if (bgVideoEl) {
    setupVideoEvents();
    setupHLS();
  }
}

function setupVideoEvents() {
  bgVideoEl.loop = false;

  bgVideoEl.addEventListener("ended", () => {
    bgVideoEl.currentTime = 0;
    bgVideoEl.play().catch(err => console.warn("play() failed:", err));
  });

  const markVideoReady = () => {
    if (!videoReady) {
      console.log("Video ready");
    }
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

function setupHLS() {
  if (HlsGlobal && HlsGlobal.isSupported()) {
    console.log("Using HLS.js");

    hlsInstance = new HlsGlobal({
      enableWorker: true,
      lowLatencyMode: false,
      maxBufferLength: 60,
      maxBufferSize: 120 * 1000 * 1000,
      maxMaxBufferLength: 120,
      backBufferLength: 0,
      startPosition: 0
    });

    hlsInstance.on(HlsGlobal.Events.ERROR, (event, data) => {
      console.warn("HLS.js error:", data);

      if (data.fatal) {
        if (data.type === HlsGlobal.ErrorTypes.MEDIA_ERROR) {
          hlsInstance.recoverMediaError();
        } else if (data.type === HlsGlobal.ErrorTypes.NETWORK_ERROR) {
          hlsInstance.startLoad();
        } else {
          hlsInstance.destroy();
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
export function updateVideoFrame() {
  if (!bgVideoEl || !videoReady || !videoSourceReady || !videoLayerReady) return false;
  if (!bgVideoEl.videoWidth || !bgVideoEl.videoHeight) return false;

  const currentTime = bgVideoEl.currentTime;
  const hasAdvanced = currentTime !== lastVideoTime;

  if (hasVideoFrame && !hasAdvanced) return true;

  const sourceW = bgVideoEl.videoWidth;
  const sourceH = bgVideoEl.videoHeight;

  // Resize raw source canvas if needed
  if (videoSourceWidth !== sourceW || videoSourceHeight !== sourceH) {
    videoSourceCanvas.width = sourceW;
    videoSourceCanvas.height = sourceH;
    videoSourceWidth = sourceW;
    videoSourceHeight = sourceH;
  }

  // Resize p5 graphics layer if needed
  if (videoLayer.width !== awrWeb.width || videoLayer.height !== awrWeb.height) {
    videoLayer.resizeCanvas(awrWeb.width, awrWeb.height);
    videoLayer.pixelDensity(1);
    videoLayerCtx = videoLayer.drawingContext;
  }

  try {
    // Copy raw video frame
    videoSourceCtx.drawImage(bgVideoEl, 0, 0, sourceW, sourceH);

    // Draw scaled frame into p5 graphics layer
    videoLayerCtx.save();
    videoLayerCtx.clearRect(0, 0, videoLayer.width, videoLayer.height);
    videoLayerCtx.drawImage(videoSourceCanvas, 0, 0, videoLayer.width, videoLayer.height);
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
  awrWeb.tint(255, alpha);
  awrWeb.image(videoLayer, 0, 0, awrWeb.width, awrWeb.height);
  awrWeb.pop();
}
