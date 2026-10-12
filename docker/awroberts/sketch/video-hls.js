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

  // Initialize independent graphics surfaces
  initRenderLayers(awrWeb);

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
  let waitingTimeout = null; // High-precision track supervisor

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

    // HARD RECOVERY BACKUP: If the hardware decoder hangs on a native waiting event
    // for 3 seconds straight, bypass soft hooks and force a live-edge buffer jump.
    if (!waitingTimeout) {
      waitingTimeout = setTimeout(() => {
        if (!bgVideoEl || bgVideoEl.paused || bgVideoEl.ended) return;
        console.warn("Watchdog: Stuck on native waiting event for 3s — forcing live jump");

        if (hlsInstance) {
          hlsInstance.stopLoad();
          hlsInstance.startLoad(-1);
          const livePos = hlsInstance.liveSyncPosition;
          if (livePos != null && isFinite(livePos)) {
            bgVideoEl.currentTime = Math.max(0, livePos - 2);
          }
        }

        bgVideoEl.play()
          .then(() => {
            isRecoveringFromStall = false;
            if (waitingTimeout) { clearTimeout(waitingTimeout); waitingTimeout = null; }
          })
          .catch(err => console.warn("Waiting timeout recovery play failed:", err));
      }, 3000);
    }
  });

  bgVideoEl.addEventListener("playing", () => {
    isRecoveringFromStall = false;
    if (stalledTimer) { clearTimeout(stalledTimer); stalledTimer = null; }
    // Cleanly dump active waiting timers as stream pixels resume drawing
    if (waitingTimeout) { clearTimeout(waitingTimeout); waitingTimeout = null; }
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
      lowLatencyMode: true,            // Sync rapidly with live stream edge
      maxBufferLength: 15,             // Slightly lowered to force faster clip discard cycles
      maxBufferSize: 30 * 1000 * 1000, // Reduced safety limit to clear unplayed frame junk faster
      maxMaxBufferLength: 30,
      backBufferLength: 5,             // Lower values limit structural backtracking lag
      startPosition: -1,
      liveSyncDurationCount: 3,
      liveMaxLatencyDurationCount: 6
    });

    hlsInstance.loadSource(VIDEO_URL);
    hlsInstance.attachMedia(bgVideoEl);

    // Track sequential stall attempts to detect nudge failures
    let continuousStallCount = 0;

    hlsInstance.on(HlsGlobal.Events.ERROR, (event, data) => {
      console.warn(`HLS.js error [fatal=${data.fatal}] type=${data.type} details=${data.details}`, data);

      if (!data.fatal && data.details === HlsGlobal.ErrorDetails.BUFFER_STALLED_ERROR) {
        continuousStallCount++;
        isRecoveringFromStall = true;

        if (continuousStallCount > 3) {
          console.warn("HLS.js nudges failing — forcing hard stream edge recovery");
          continuousStallCount = 0;

          // 1. Terminate stalled network request cycles
          hlsInstance.stopLoad();

          // 2. Clear out the broken frame tracks from the browser's hardware pipeline
          if (typeof hlsInstance.skipToExtension === 'function') {
            hlsInstance.skipToExtension();
          }

          // 3. Re-sync HLS.js with the live broadcast playlist edge
          hlsInstance.startLoad(-1);

          // 4. SMART TARGET SEEK: Target 1 full fragment duration back from live edge
          // Because your chunks are ~8.34s long, backing off 10s drops the player
          // safely into a fully downloaded, clean, uncorrupted segment.
          const livePos = hlsInstance.liveSyncPosition;
          if (livePos != null && isFinite(livePos)) {
            bgVideoEl.currentTime = Math.max(0, livePos - 10);
          } else {
            // Fallback: Jump ahead past the stuck frame boundary manually
            bgVideoEl.currentTime = bgVideoEl.currentTime + 10;
          }

          // 5. Force invoke the element layout track to clear the freeze
          bgVideoEl.play()
            .then(() => {
              // Clear recovery locks strictly on a successful play resolution
              isRecoveringFromStall = false;
            })
            .catch(err => {
              console.warn("Hard recovery play jump failed:", err);
              isRecoveringFromStall = false;
            });
        } else {
          console.log("HLS.js buffer stalled — nudging load (Attempt " + continuousStallCount + ")");
          hlsInstance.startLoad(-1);
        }
        return;
      }

      // Handle structural fatal errors
      if (data.fatal) {
        continuousStallCount = 0;
        if (data.type === HlsGlobal.ErrorTypes.MEDIA_ERROR) {
          console.warn("HLS.js fatal media error — recovering");
          hlsInstance.recoverMediaError();
        } else if (data.type === HlsGlobal.ErrorTypes.NETWORK_ERROR) {
          console.warn("HLS.js fatal network error — restarting load");
          hlsInstance.startLoad(-1);
        } else {
          console.error("Unrecoverable HLS error encountered. Rebuilding engine...");
          hlsInstance.destroy();
          setupHLS();
        }
      }
    });

    // Reset loop count whenever fragments play smoothly
    hlsInstance.on(HlsGlobal.Events.FRAG_CHANGED, () => {
      continuousStallCount = 0;
    });

  } else if (bgVideoEl.canPlayType("application/vnd.apple.mpegurl")) {
    console.log("Using Native Safari HLS engine");
    bgVideoEl.src = VIDEO_URL;
  }
}
