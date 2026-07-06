// ui.js

// -----------------------------
// INTERNAL P5 INSTANCE
// -----------------------------
let awrWeb = null;

export function bindUIP5(p) {
  awrWeb = p;
}

// -----------------------------
// UI STATE
// -----------------------------
export let emailText = 'info@awroberts.co.uk';
let emailSize;
let isHoveringEmail = false;

let icons = {};
let socialLinks = [
  { imgKey: 'github', url: 'https://github.com/awroberts' },
  { imgKey: 'linkedin', url: 'https://www.linkedin.com/in/alexander-roberts-53563312b/' },
  { imgKey: 'bandcamp', url: 'https://chewvalleytapes.bandcamp.com/' },
  { imgKey: 'youtube', url: 'https://www.youtube.com/@ChewValleyTapes' }
];

let hoveringSocial = -1;
let glowColor = [127, 203, 255];
let fadeStartTime;
let diag;

// -----------------------------
// PRELOAD
// -----------------------------
export async function preloadUIAssets() {
  diag = await fetch('/deployment.json').then(r => r.json()).catch(() => null);

  [
    icons.github,
    icons.linkedin,
    icons.bandcamp,
    icons.youtube,
    icons['logo-kubernetes'],
    icons['logo-helm'],
    icons['logo-traefik'],
    icons['logo-hlsjs'],
    icons['logo-p5js'],
    icons['logo-cilium'],
    icons['logo-docker'],
    icons['logo-containerd'],
    icons['logo-gatewayapi'],
  ] = await Promise.all([
    awrWeb.loadImage('/assets/github.png'),
    awrWeb.loadImage('/assets/linkedin.png'),
    awrWeb.loadImage('/assets/bandcamp.png'),
    awrWeb.loadImage('/assets/youtube.png'),
    awrWeb.loadImage('/assets/logos/kubernetes.png'),
    awrWeb.loadImage('/assets/logos/helm.png'),
    awrWeb.loadImage('/assets/logos/traefik.png'),
    awrWeb.loadImage('/assets/logos/hlsjs.png'),
    awrWeb.loadImage('/assets/logos/p5js.png'),
    awrWeb.loadImage('/assets/logos/cilium.png'),
    awrWeb.loadImage('/assets/logos/docker.png'),
    awrWeb.loadImage('/assets/logos/containerd.png'),
    awrWeb.loadImage('/assets/logos/gatewayapi.png'),
  ]);
}

// -----------------------------
// INIT
// -----------------------------
export function initUI() {
  emailSize = awrWeb.constrain(
    awrWeb.min(awrWeb.windowWidth, awrWeb.windowHeight) * 0.05,
    16,
    70
  );

  awrWeb.textFont('CURWENFONT');
  awrWeb.textSize(emailSize);
  awrWeb.textAlign(awrWeb.RIGHT, awrWeb.TOP);

  fadeStartTime = awrWeb.millis();
}

// -----------------------------
// HIT TEST HELPERS
// -----------------------------
export function getEmailHitRect() {
  const margin = 30;
  const x = awrWeb.width - margin;
  const y = margin;

  awrWeb.textSize(emailSize);
  const textW = awrWeb.textWidth(emailText);

  const padLeft = emailSize * 0.8;
  const padRight = emailSize * 0.2;
  const padY = emailSize * 0.25;

  return {
    left: x - textW - padLeft,
    right: x + padRight,
    top: y - padY,
    bottom: y + emailSize + padY,
    x,
    y
  };
}

function pointInRect(px, py, rect) {
  return px >= rect.left && px <= rect.right && py >= rect.top && py <= rect.bottom;
}

function pointInBox(px, py, x, y, size) {
  return px >= x && px <= x + size && py >= y && py <= y + size;
}

// -----------------------------
// GLOW
// -----------------------------
function drawGlow(x, y, w, h, alpha) {
  awrWeb.push();
  awrWeb.noStroke();
  awrWeb.fill(glowColor[0], glowColor[1], glowColor[2], alpha * 0.6);
  awrWeb.drawingContext.filter = 'blur(12px)';
  awrWeb.rect(x, y, w, h, 6);
  awrWeb.pop();
}

// -----------------------------
// EMAIL
// -----------------------------
function drawEmail() {
  const hit = getEmailHitRect();

  isHoveringEmail =
    awrWeb.mouseX >= hit.left &&
    awrWeb.mouseX <= hit.right &&
    awrWeb.mouseY >= hit.top &&
    awrWeb.mouseY <= hit.bottom;

  if (isHoveringEmail) {
    drawGlow(hit.left, hit.top, hit.right - hit.left, hit.bottom - hit.top, 255);
    awrWeb.cursor(awrWeb.HAND);
  } else {
    drawGlow(hit.left, hit.top, hit.right - hit.left, hit.bottom - hit.top, 0);
  }

  awrWeb.textSize(isHoveringEmail ? emailSize * 1.05 : emailSize);
  awrWeb.fill(255);
  awrWeb.textAlign(awrWeb.RIGHT, awrWeb.TOP);
  awrWeb.text(emailText, hit.x, hit.y);
}

function openEmail() {
  window.location.href = 'mailto:info@awroberts.co.uk';
}

// -----------------------------
// SOCIAL ICONS
// -----------------------------
function drawSocialIcons() {
  const size = emailSize * 0.8;
  const margin = 30;
  const gap = 14;
  const xStart = margin;
  const yStart = margin + 10;

  hoveringSocial = -1;

  const fadeProgress = awrWeb.constrain((awrWeb.millis() - fadeStartTime) / 1000, 0, 1);
  const alpha = fadeProgress * 255;

  socialLinks.forEach((item, i) => {
    const col = i % 2;
    const row = Math.floor(i / 2);
    const x = xStart + col * (size + gap);
    const y = yStart + row * (size + gap) - 5;

    const icon = icons[item.imgKey];

    const isHover =
      awrWeb.mouseX > x &&
      awrWeb.mouseX < x + size &&
      awrWeb.mouseY > y &&
      awrWeb.mouseY < y + size;

    if (isHover) {
      hoveringSocial = i;
      awrWeb.cursor(awrWeb.HAND);
    }

    const glowAlpha = isHover ? 255 : 0;
    const glowPad = 8;

    drawGlow(
      x - glowPad,
      y - glowPad,
      size + glowPad * 2,
      size + glowPad * 2,
      glowAlpha
    );

    if (icon && icon.width > 0 && icon.height > 0) {
      awrWeb.push();
      awrWeb.drawingContext.globalAlpha = alpha / 255;
      awrWeb.image(icon, x, y, size, size);
      awrWeb.pop();
    }
  });
}

function openSocial(index) {
  if (index < 0 || index >= socialLinks.length) return;
  window.open(socialLinks[index].url, '_blank', 'noopener,noreferrer');
}

// -----------------------------
// DEPLOYMENT INFO
// -----------------------------
function drawDeploymentInfo() {
  if (!diag) return;

  const baseSize = awrWeb.min(awrWeb.windowWidth, awrWeb.windowHeight) * 0.02;
  awrWeb.textSize(baseSize);
  awrWeb.textAlign(awrWeb.LEFT);
  awrWeb.fill(255);

  const margin = 30;
  const x = margin;

  const entries = [
    { label: 'containerd',              logoKey: 'logo-containerd', value: diag.containerd?.version ?? 'N/A' },
    { label: 'docker',                  logoKey: 'logo-docker',     value: diag.docker?.version ?? 'N/A' },
    { label: 'cilium',                  logoKey: 'logo-cilium',     value: diag.cilium?.version ?? 'N/A' },   // UPDATED
    { label: 'kubernetes',              logoKey: 'logo-kubernetes', value: diag.kubernetes?.version ?? 'N/A' },
    { label: 'gateway api',             logoKey: 'logo-gatewayapi', value: diag.gatewayAPI?.version ?? 'N/A' },
    { label: 'helm',                    logoKey: 'logo-helm',       value: diag.helm?.version ?? 'N/A' },
    { label: 'traefik',                 logoKey: 'logo-traefik',    value: diag.traefik?.build?.version ?? 'N/A' },
    { label: 'hls.js',                  logoKey: 'logo-hlsjs',      value: diag.libraries?.['hls.js']?.version ?? 'N/A' },
    { label: 'p5.js',                   logoKey: 'logo-p5js',       value: diag.libraries?.['p5.js']?.version ?? 'N/A' },
    { spacer: true },
    { label: 'cluster',                 value: diag.awroberts?.service?.clusterIP ?? 'N/A' },
    { label: 'web pod',                 value: diag.pods?.web?.ip ?? 'N/A' },
    { label: 'background video pod',    value: diag.pods?.backgroundVideo?.ip ?? 'N/A' },
    { label: 'background ffmpeg pod',   value: diag.pods?.backgroundFfmpeg?.ip ?? 'N/A' }
  ];

  const boxSize = baseSize;
  const labelColW = Math.max(
    baseSize * 4,
    entries.filter(e => !e.logoKey).reduce((max, e) => Math.max(max, awrWeb.textWidth(e.label + ':')), 0)
  );
  const maxValueW = entries.filter(e => !e.spacer).reduce((max, e) => Math.max(max, awrWeb.textWidth(e.value)), 0);
  const rightEdge = x + labelColW + baseSize * 0.8 + maxValueW;

  let y = awrWeb.height - margin - (baseSize * 1.3 * entries.length);

  for (const { label, logoKey, value, spacer } of entries) {
    if (!spacer) {
      if (logoKey) {
        const img = icons[logoKey];
        if (img && img.width > 0) {
          const scale = Math.min(boxSize / img.width, boxSize / img.height);
          const w = img.width * scale;
          const h = img.height * scale;
          const cx = x + (boxSize - w) / 2;
          const cy = y + (boxSize - h) / 2;

          awrWeb.image(img, cx, cy, w, h);
        }
      } else {
        awrWeb.textAlign(awrWeb.LEFT, awrWeb.TOP);
        awrWeb.text(label + ':', x, y);
      }

      awrWeb.textAlign(awrWeb.RIGHT, awrWeb.TOP);
      awrWeb.text(value, rightEdge, y);
    }
    y += baseSize * 1.3;
  }
}

// -----------------------------
// POINTER HANDLING
// -----------------------------
export function handlePointerActivation(px, py) {
  const emailHit = getEmailHitRect();
  if (pointInRect(px, py, emailHit)) {
    openEmail();
    return true;
  }

  const size = emailSize * 0.8;
  const margin = 30;
  const gap = 14;
  const xStart = margin;
  const yStart = margin + 10;

  for (let i = 0; i < socialLinks.length; i++) {
    const col = i % 2;
    const row = Math.floor(i / 2);
    const x = xStart + col * (size + gap);
    const y = yStart + row * (size + gap);

    if (pointInBox(px, py, x, y, size)) {
      openSocial(i);
      return true;
    }
  }

  return false;
}

// -----------------------------
// RESIZE
// -----------------------------
export function handleResize() {
  if (emailSize) {
    emailSize = awrWeb.constrain(
      awrWeb.min(awrWeb.windowWidth, awrWeb.windowHeight) * 0.05,
      16,
      70
    );
    awrWeb.textSize(emailSize);
  }
}

// -----------------------------
// DRAW UI WRAPPER
// -----------------------------
export function drawUI() {
  drawEmail();
  drawSocialIcons();
  drawDeploymentInfo();
}
