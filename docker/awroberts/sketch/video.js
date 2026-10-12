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

// Flag to let the watchdog know HLS is actively trying to resolve a stall
let isRecoveringFromStall = false;
let watchdogFrozenSince = null;

const HlsGlobal = window.Hls;

// -----------------------------
// MOBILE / DESKTOP STREAM SELECTION
// -----------------------------
const isMobile =
  /Android|iPhone|iPad|iPod|Opera Mini|IEMobile/i.test(navigator.userAgent);

const VIDEO_URL = isMobile
  ? "https://awroberts.co.uk/stream/mobile/index.m3u8?v=" + Date.now()
  : "https://awroberts.co.uk/stream/index.m3u8?v=" + Date.now();

const POSTER_URL = "/background-poster.png";

// -----------------------------
// PRELOAD
// -----------------------------
export async function preloadVideoAssets() {
  bgPosterImg = await awrWeb.loadImage(POSTER_URL + '?v=' + Date.now());
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
  // Set willReadFrequently to optimize p5.js loop getImageData queries
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

    // Do not count stalling as frozen if stream engine is actively recovering
    if (bgVideoEl.paused || isRecoveringFromStall) {
      watchdogFrozenSince = null;
      watchdogLastTime = bgVideoEl.currentTime;
      return;
    }

    const ct = bgVideoEl.currentTime;
    if (ct === watchdogLastTime) {
      if (watchdogFrozenSince === null) {
        watchdogFrozenSince = Date.now();
      } else if (Date.now() - watchdogFrozenSince > 5000) {
        console.warn("Video watchdog: frozen, restarting HLS");
        watchdogFrozenSince = null;
        isRecoveringFromStall = true;

        if (hlsInstance) {
          hlsInstance.stopLoad();
          hlsInstance.startLoad(-1);
        } else {
          // Native HLS (Safari) — seek to live edge to force re-buffering
          const seekable = bgVideoEl.seekable;
          if (seekable && seekable.length > 0) {
            bgVideoEl.currentTime = seekable.end(seekable.length - 1);
          }
        }
        bgVideoEl.play()
          .then(() => { isRecoveringFromStall = false; })
          .catch(err => console.warn("Watchdog play() failed:", err));
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

  let stalledTimer = null;

  const recoverStall = () => {
    if (stalledTimer) return;
    isRecoveringFromStall = true;
    stalledTimer = setTimeout(() => {
      stalledTimer = null;
      if (!bgVideoEl || bgVideoEl.ended) {
        isRecoveringFromStall = false;
        return;
      }
      console.warn("Video stall recovery triggered");
      if (hlsInstance) {
        const livePos = hlsInstance.liveSyncPosition;
        if (livePos != null && isFinite(livePos)) bgVideoEl.currentTime = livePos;
        hlsInstance.startLoad(-1);
      }
      bgVideoEl.play()
        .then(() => { isRecoveringFromStall = false; })
        .catch(err => {
          console.warn("Stall recovery play() failed:", err);
          isRecoveringFromStall = false;
        });
    }, 3000);
  };

  bgVideoEl.addEventListener("stalled", () => {
    console.warn("Video event: stalled — paused=" + bgVideoEl.paused + " ended=" + bgVideoEl.ended + " t=" + bgVideoEl.currentTime.toFixed(2));
    recoverStall();
  });

  bgVideoEl.addEventListener("waiting", () => {
    console.warn("Video event: waiting — paused=" + bgVideoEl.paused + " ended=" + bgVideoEl.ended + " t=" + bgVideoEl.currentTime.toFixed(2));
    isRecoveringFromStall = true;
  });

  bgVideoEl.addEventListener("playing", () => {
    isRecoveringFromStall = false;
    if (stalledTimer) { clearTimeout(stalledTimer); stalledTimer = null; }
  });

  bgVideoEl.addEventListener("pause", () => {
    console.warn("Video event: pause — ended=" + bgVideoEl.ended + " t=" + bgVideoEl.currentTime.toFixed(2));
    if (!bgVideoEl.ended) {
      bgVideoEl.play().catch(err => console.warn("Auto-resume play() failed:", err));
    }
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
      lowLatencyMode: true,            // Switched to true to sync faster to live edge
      maxBufferLength: 20,             // Raised from 10 to provide fallback frames during lag spikes
      maxBufferSize: 50 * 1000 * 1000, // Raised to 50MB to support higher bitrate bursts
      maxMaxBufferLength: 40,          // Raised from 20 to widen network buffer safety limits
      backBufferLength: 10,            // Keeps last 10s of frames in memory to stop layout stuttering
      startPosition: -1,
      liveSyncDurationCount: 3,        // Safer live synchronization latency threshold
      liveMaxLatencyDurationCount: 6
    });

    // Pass the active URL string to your hls instance
    hlsInstance.loadSource(VIDEO_URL);
    hlsInstance.attachMedia(bgVideoEl);

    hlsInstance.on(HlsGlobal.Events.ERROR, (event, data) => {
      console.warn(`HLS.js error [fatal=${data.fatal}] type=${data.type} details=${data.details}`, data);

      if (!data.fatal && data.details === HlsGlobal.ErrorDetails.BUFFER_STALLED_ERROR) {
        console.warn("HLS.js buffer stalled — nudging load");
        isRecoveringFromStall = true;
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
          console.error("Unrecoverable HLS error encountered. Destroying and rebuilding...");
          hlsInstance.destroy();
          setupHLS();
        }
      }
    });
  } else if (bgVideoEl.canPlayType("application/vnd.apple.mpegurl")) {
    // Fallback for native Safari implementations
    console.log("Using Native Safari HLS engine");
    bgVideoEl.src = VIDEO_URL;
  }
}
