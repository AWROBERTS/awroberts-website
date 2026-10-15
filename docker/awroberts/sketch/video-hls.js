// video-hls.js
import { initRenderLayers } from './video-render.js';

// -----------------------------
// INTERNAL P5 INSTANCE
// -----------------------------
export let awrWeb = null;

export function bindVideoP5(p) {
  awrWeb = p;
}

// -----------------------------
// VIDEO STATE
// -----------------------------
export let bgVideoEl;
export let hlsInstance = null;
export let videoReady = false;
export let bgPosterImg = null;

// Watchdog state synchronization flags
export let isRecoveringFromStall = false;
let watchdogFrozenSince = null;

// File-level counter accessible by both setupVideoEvents and setupHLS
let continuousStallCount = 0;

const HlsGlobal = window.Hls;

// -----------------------------
// MOBILE / DESKTOP SETUP SELECTION
// -----------------------------
export const isMobile =
  /Android|iPhone|iPad|iPod|Opera Mini|IEMobile/i.test(navigator.userAgent);

// Direct desktop to your pristine 4K copy stream path
const VIDEO_URL = "/stream/index.m3u8?v=" + Date.now();
const POSTER_URL = "/background-poster.png";

// Mobile image-loop configuration timer pointer
let mobileTimer = null;

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

  if (document.readyState !== "complete" && document.readyState !== "interactive") {
    console.log("DOM not ready — retrying initVideoSystem()");
    return setTimeout(initVideoSystem, 50);
  }

  // Initialize independent graphics surfaces for the canvas sketches
  initRenderLayers(awrWeb);

  // ----------------------------------------------------
  // MOBILE FALLBACK DUAL-BUFFER FILE RELOADER LOOP
  // ----------------------------------------------------
  if (isMobile) {
    console.log("Mobile device detected: Activating Dual-Buffer Image Cross-Dissolve Engine");

    // Set videoReady to true so p5 knows it can draw the bgPosterImg asset layer
    videoReady = true;

    if (mobileTimer) clearInterval(mobileTimer);

    // Query the server RAM highway precisely on your 2-second heartbeat
    mobileTimer = setInterval(() => {
      const cacheBustUrl = POSTER_URL + '?v=' + Date.now();

      // Use native p5 callback parameters
      awrWeb.loadImage(
        cacheBustUrl,
        (freshPoster) => {
          if (freshPoster) {
            // Import is resolved immediately without background thread throttling
            import('./video-render.js').then((module) => {
              module.stageNextMobileFrame(freshPoster);
            });
          }
        },
        (err) => {
          console.warn("Mobile dual-buffer loader encountered a packet fetch slip", err);
        }
      );
    }, 2000);

    return; // Exit completely. No heavy video elements or watchdogs needed for mobile!
  }

  // ----------------------------------------------------
  // DESKTOP PIPELINE CODE PATH
  // ----------------------------------------------------
  bgVideoEl = document.getElementById("bg-video");

  if (!bgVideoEl) {
    console.warn("bgVideoEl not found — retrying initVideoSystem()");
    return setTimeout(initVideoSystem, 50);
  }

  bgVideoEl.muted = true;
  bgVideoEl.defaultMuted = true;
  bgVideoEl.setAttribute('playsinline', '');

  console.log("initVideoSystem(): Desktop video element found:", bgVideoEl);

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
      const seekable = bgVideoEl.seekable;
      if (seekable && seekable.length > 0) {
        bgVideoEl.currentTime = seekable.end(seekable.length - 1);
      }
    }
    if (bgVideoEl.paused) {
      bgVideoEl.play().catch(err => console.warn("play() after visibility:", err));
    }
  });

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
// VIDEO EVENTS (DESKTOP ONLY)
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
  let waitingTimeout = null;
  let dynamicPauseDebounce = null;

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

    if (!waitingTimeout) {
      waitingTimeout = setTimeout(() => {
        if (!bgVideoEl || bgVideoEl.paused || bgVideoEl.ended) return;
        console.warn("Watchdog: Stuck on native waiting event for 3s — forcing live jump");

        if (hlsInstance) {
          hlsInstance.stopLoad();
          hlsInstance.startLoad(-1);
          const livePos = hlsInstance.liveSyncPosition;
          if (livePos != null && isFinite(livePos)) {
            bgVideoEl.currentTime = Math.max(0, livePos - 10);
          }
        }

        bgVideoEl.play()
          .then(() => {
            isRecoveringFromStall = false;
            continuousStallCount = 0;
            if (waitingTimeout) { clearTimeout(waitingTimeout); waitingTimeout = null; }
          })
          .catch(err => console.warn("Waiting timeout recovery play failed:", err));
      }, 3000);
    }
  });

  bgVideoEl.addEventListener("playing", () => {
    isRecoveringFromStall = false;
    continuousStallCount = 0;
    if (stalledTimer) { clearTimeout(stalledTimer); stalledTimer = null; }
    if (waitingTimeout) { clearTimeout(waitingTimeout); waitingTimeout = null; }
    if (dynamicPauseDebounce) { clearTimeout(dynamicPauseDebounce); dynamicPauseDebounce = null; }
  });

  bgVideoEl.addEventListener("pause", () => {
    console.warn("Video event: pause intercepted — ended=" + bgVideoEl.ended + " t=" + bgVideoEl.currentTime.toFixed(2));

    if (bgVideoEl.ended || isRecoveringFromStall) return;

    if (!dynamicPauseDebounce) {
      dynamicPauseDebounce = setTimeout(() => {
        dynamicPauseDebounce = null;
        if (!bgVideoEl || !bgVideoEl.paused) return;
        console.log("Watchdog: Resolving unintended layout background pause — forcing play");
        bgVideoEl.play().catch(err => console.warn("Watchdog dynamic pause override failed:", err));
      }, 150);
    }
  });
}

// -----------------------------
// HLS INITIALIZATION ENGINE (DESKTOP ONLY)
// -----------------------------
function setupHLS() {
  if (HlsGlobal && HlsGlobal.isSupported()) {
    console.log("Using Desktop HLS.js engine wrapper");

    const hlsConfig = {
      enableWorker: true,
      lowLatencyMode: false,
      liveSyncDurationCount: 3,
      liveMaxLatencyDurationCount: 6,
      maxBufferLength: 10,
      maxMaxBufferLength: 20,
      maxBufferSize: 50 * 1000 * 1000,
      maxFragLookUpTolerance: 0.5,
      maxBufferHole: 0.5,
      lowBufferWatchdogPeriod: 0.5,
      highBufferWatchdogPeriod: 2
    };

    hlsInstance = new HlsGlobal(hlsConfig);
    hlsInstance.loadSource(VIDEO_URL);
    hlsInstance.attachMedia(bgVideoEl);

    hlsInstance.on(HlsGlobal.Events.MANIFEST_PARSED, () => {
      console.log("setupHLS(): HlsGlobal manifest parsed successfully.");
      videoReady = true;
      bgVideoEl.play().catch(err => console.warn("Initial active HLS play failed:", err));
    });

    hlsInstance.on(HlsGlobal.Events.ERROR, (event, data) => {
      if (data.fatal) {
        console.warn("Fatal HLS error encountered:", data.details);
        switch (data.type) {
          case HlsGlobal.ErrorTypes.NETWORK_ERROR:
            hlsInstance.startLoad();
            break;
          case HlsGlobal.ErrorTypes.MEDIA_ERROR:
            hlsInstance.recoverMediaError();
            break;
          default:
            setupHLS();
            break;
        }
      }
    });
  }
}
