let bgVideoEl;
let hlsInstance = null;
let videoReady = false;
let videoFadeStart = null;
let videoFadeDuration = 1200;

// p5 render/effects layer
let videoLayer = null;

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

function preload() {
  curwenFont = loadFont('/awroberts-media/CURWENFONT.ttf');
  diag = loadJSON('/deployment.json');

  icons.github = loadImage('/assets/github.png');
  icons.linkedin = loadImage('/assets/linkedin.png');
  icons.bandcamp = loadImage('/assets/bandcamp.png');
}

function setup() {
  pixelDensity(1);

  const canvas = createCanvas(windowWidth, windowHeight);
  canvas.parent('canvas-container');
  canvas.style('position', 'absolute');
  canvas.style('top', '0');
  canvas.style('left', '0');
  canvas.style('z-index', '1');

  videoLayer = createGraphics(windowWidth, windowHeight);
  videoLayer.pixelDensity(1);

  bgVideoEl = document.getElementById("bg-video");

  if (bgVideoEl && "requestVideoFrameCallback" in bgVideoEl) {
    const onFirstFrame = () => {
      console.log("First decoded frame detected");
      videoReady = true;
      if (videoFadeStart === null) {
        videoFadeStart = millis();
      }
    };
    bgVideoEl.requestVideoFrameCallback(onFirstFrame);
  } else if (bgVideoEl) {
    bgVideoEl.addEventListener("canplay", () => {
      console.log("Video canplay fired");
      videoReady = true;
      if (videoFadeStart === null) {
        videoFadeStart = millis();
      }
    });
  }

  if (bgVideoEl) {
    if (Hls.isSupported()) {
      hlsInstance = new Hls({
        enableWorker: true,
        lowLatencyMode: false,
        liveSyncDurationCount: 3,
        liveMaxLatencyDurationCount: 8,
        maxLiveSyncPlaybackRate: 1.25,
        backBufferLength: 30,
        maxBufferLength: 20,
        maxMaxBufferLength: 40
      });

      hlsInstance.on(Hls.Events.ERROR, (event, data) => {
        console.warn("HLS.js error:", data);

        if (!data.fatal && data.details === "bufferStalledError") {
          if (bgVideoEl.buffered && bgVideoEl.buffered.length) {
            const end = bgVideoEl.buffered.end(bgVideoEl.buffered.length - 1);
            const target = Math.max(end - 1.5, 0);
            bgVideoEl.currentTime = target;
            bgVideoEl.play().catch(err => console.warn("play() failed:", err));
          }
          return;
        }

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
// Copy video directly into p5.Graphics background layer
// ---------------------------------------------------
function updateVideoLayer() {
  if (!bgVideoEl) return;
  if (!videoReady) return;
  if (!videoLayer) return;
  if (!bgVideoEl.videoWidth || !bgVideoEl.videoHeight) return;

  if (videoLayer.width !== width || videoLayer.height !== height) {
    videoLayer.resizeCanvas(width, height);
    videoLayer.pixelDensity(1);
  }

  const ctx = videoLayer.drawingContext;

  try {
    ctx.save();
    ctx.clearRect(0, 0, videoLayer.width, videoLayer.height);
    ctx.drawImage(bgVideoEl, 0, 0, videoLayer.width, videoLayer.height);
    ctx.restore();
  } catch (err) {
    console.warn("Video layer update skipped:", err);
  }
}

function draw() {
  clear();

  if (videoReady && videoLayer) {
    updateVideoLayer();

    let alpha = 255;
    if (videoFadeStart !== null) {
      const t = (millis() - videoFadeStart) / videoFadeDuration;
      alpha = constrain(t * 255, 0, 255);
    }

    push();
    tint(255, alpha);
    image(videoLayer, 0, 0, width, height);
    pop();
  }

  drawEmail();
  drawSocialIcons();
  drawDeploymentInfo();
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
  pop();
}

// ----------------------------
// EMAIL
// ----------------------------
function drawEmail() {
  const margin = 30;
  const x = width - margin;
  const y = margin;

  textSize(emailSize);
  const textW = textWidth(emailText);

  const padLeft = emailSize * 0.8;
  const padRight = emailSize * 0.2;
  const padY = emailSize * 0.25;

  const hitLeft = x - textW - padLeft;
  const hitRight = x + padRight;
  const hitTop = y - padY;
  const hitBottom = y + emailSize + padY;

  isHoveringEmail =
    mouseX >= hitLeft &&
    mouseX <= hitRight &&
    mouseY >= hitTop &&
    mouseY <= hitBottom;

  if (isHoveringEmail) {
    drawGlow(hitLeft, hitTop, hitRight - hitLeft, hitBottom - hitTop, 255);
    cursor(HAND);
  } else {
    drawGlow(hitLeft, hitTop, hitRight - hitLeft, hitBottom - hitTop, 0);
  }

  textSize(isHoveringEmail ? emailSize * 1.05 : emailSize);
  fill(255);
  textAlign(RIGHT, TOP);
  text(emailText, x, y);
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
    `traefik: ${diag.traefik?.version ?? 'N/A'}`,
    `deployment: ${diag.deployment?.name ?? 'N/A'}`,
    `pod: ${diag.pod?.name ?? 'N/A'}`,
    `pod ip: ${diag.pod?.ip ?? 'N/A'}`,
    `service cluster ip: ${diag.service?.clusterIP ?? 'N/A'}`,
    `awroberts: ${diag.build?.awroberts?.name ?? 'N/A'}:${diag.build?.awroberts?.tag ?? 'N/A'}`,
    `awroberts sha: ${diag.build?.awroberts?.sha ?? 'N/A'}`,
    `background-video: ${diag.build?.backgroundVideo?.name ?? 'N/A'}:${diag.build?.backgroundVideo?.tag ?? 'N/A'}`,
    `background-video sha: ${diag.build?.backgroundVideo?.sha ?? 'N/A'}`
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
function mousePressed() {
  if (isHoveringEmail) {
    window.location.href = 'mailto:info@awroberts.co.uk';
    return;
  }

  if (hoveringSocial !== -1) {
    window.open(socialLinks[hoveringSocial].url, '_blank');
  }
}

function touchStarted() {
  if (touches.length > 0) {
    const tx = touches[0].x;
    const ty = touches[0].y;

    const margin = 30;
    const x = width - margin;
    const y = margin;
    const textW = textWidth(emailText);

    if (tx > x - textW && tx < x && ty > y && ty < y + emailSize) {
      window.location.href = 'mailto:info@awroberts.co.uk';
    }
  }
  return false;
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);

  if (videoLayer) {
    videoLayer.resizeCanvas(windowWidth, windowHeight);
    videoLayer.pixelDensity(1);
  }

  emailSize = constrain(min(windowWidth, windowHeight) * 0.05, 16, 70);
  textSize(emailSize);
}