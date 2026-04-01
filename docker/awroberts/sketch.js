let bgVideoEl;
let videoReady = false;
let videoFadeStart = null;
let videoFadeDuration = 1200;

// NEW: buffer canvas + context
let videoBufferCanvas = null;
let videoBufferCtx = null;
let bufferReady = false; // NEW: ensures p5 never draws undefined

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

const VIDEO_URL = "https://awroberts.co.uk/stream/index.m3u8";

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

  // Get video element
  bgVideoEl = document.getElementById("bg-video");

  // NEW: wait for buffer canvas to exist
  waitForBufferCanvas();

  // Detect first decoded frame
  if ("requestVideoFrameCallback" in bgVideoEl) {
    bgVideoEl.requestVideoFrameCallback(() => {
      videoReady = true;
      videoFadeStart = millis();
    });
  } else {
    bgVideoEl.addEventListener("canplay", () => {
      videoReady = true;
      videoFadeStart = millis();
    });
  }

  // Load HLS
  if (Hls.isSupported()) {
    const hls = new Hls();
    hls.loadSource(VIDEO_URL);
    hls.attachMedia(bgVideoEl);
    hls.on(Hls.Events.MANIFEST_PARSED, () => {
      bgVideoEl.play();
    });
  } else if (bgVideoEl.canPlayType("application/vnd.apple.mpegurl")) {
    bgVideoEl.src = VIDEO_URL;
    bgVideoEl.play();
  }

  emailSize = constrain(min(windowWidth, windowHeight) * 0.05, 16, 70);

  textFont(curwenFont);
  textSize(emailSize);
  textAlign(RIGHT, TOP);

  fadeStartTime = millis();
}

// ---------------------------------------------------
// NEW: Wait for buffer canvas to exist before drawing
// ---------------------------------------------------
function waitForBufferCanvas() {
  videoBufferCanvas = document.getElementById("video-buffer");

  if (!videoBufferCanvas) {
    requestAnimationFrame(waitForBufferCanvas);
    return;
  }

  videoBufferCtx = videoBufferCanvas.getContext("2d");
  bufferReady = true;
}

function draw() {
  clear();

  // ---------------------------------------------------
  // NEW: update buffer canvas with video frame
  // ---------------------------------------------------
  if (bufferReady) {
    updateVideoBuffer();
  }

  // ---------------------------------------------------
  // Draw buffer canvas into p5 (instead of video)
  // ---------------------------------------------------
  if (bufferReady && videoReady) {
    let alpha = 255;

    if (videoFadeStart !== null) {
      let t = (millis() - videoFadeStart) / videoFadeDuration;
      alpha = constrain(t * 255, 0, 255);
    }

    push();
    tint(255, alpha);

    // NEW: guard to prevent undefined width crash
    if (videoBufferCanvas) {
      image(videoBufferCanvas, 0, 0, width, height);
    }

    pop();
  }

  drawEmail();
  drawSocialIcons();
  drawDeploymentInfo();
}

// ---------------------------------------------------
// NEW: draw video → buffer canvas safely
// ---------------------------------------------------
function updateVideoBuffer() {
  if (!videoReady || !bufferReady) return;

  if (
    bgVideoEl.videoWidth > 0 &&
    bgVideoEl.videoHeight > 0
  ) {
    videoBufferCanvas.width = bgVideoEl.videoWidth;
    videoBufferCanvas.height = bgVideoEl.videoHeight;

    try {
      videoBufferCtx.drawImage(bgVideoEl, 0, 0);
    } catch (err) {
      console.warn("Video frame skipped:", err);
    }
  }
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

  let fadeProgress = constrain((millis() - fadeStartTime) / 1000, 0, 1);
  let alpha = fadeProgress * 255;

  socialLinks.forEach((item, i) => {
    let x = xStart + i * spacing;
    let icon = icons[item.imgKey];

    let isHover =
      mouseX > x &&
      mouseX < x + size &&
      mouseY > y &&
      mouseY < y + size;

    if (isHover) {
      hoveringSocial = i;
      cursor(HAND);
    }

    let glowAlpha = isHover ? 255 : 0;

    drawGlow(x - 6, y - 6, size + 12, size + 12, glowAlpha);

    if (
      icon instanceof p5.Image &&
      icon.width > 0 &&
      icon.height > 0
    ) {
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
  let x = margin;

  const lines = [
    `kubernetes: ${diag.kubernetes?.version ?? 'N/A'}`,
    `helm: ${diag.helm?.version ?? 'N/A'}`,
    `traefik: ${diag.traefik?.version ?? 'N/A'}`,
    `deployment: ${diag.deployment.name}`,
    `pod: ${diag.pod.name}`,
    `pod ip: ${diag.pod.ip}`,
    `service cluster ip: ${diag.service.clusterIP}`,
    `awroberts: ${diag.build.awroberts.name}:${diag.build.awroberts.tag}`,
    `awroberts sha: ${diag.build.awroberts.sha}`,
    `background-video: ${diag.build.backgroundVideo.name}:${diag.build.backgroundVideo.tag}`,
    `background-video sha: ${diag.build.backgroundVideo.sha}`
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
    let tx = touches[0].x;
    let ty = touches[0].y;

    let margin = 30;
    let x = width - margin;
    let y = margin;
    let textW = textWidth(emailText);

    if (
      tx > x - textW &&
      tx < x &&
      ty > y &&
      ty < y + emailSize
    ) {
      window.location.href = 'mailto:info@awroberts.co.uk';
    }
  }
  return false;
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  emailSize = constrain(min(windowWidth, windowHeight) * 0.05, 16, 70);
  textSize(emailSize);
}
