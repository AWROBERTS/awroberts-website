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

  const baseSize = awrWeb.min(awrWeb.windowWidth, awrWeb.windowHeight) * 0.018;
  const rowHeight = baseSize * 1.3;
  const margin = 30;
  const boxSize = baseSize;

  // ====================================================
  // 1. BOTTOM RIGHT: PACKAGES WITH LEFT-ALIGNED LOGOS
  // ====================================================
  const softwareEntries = [
    { logoKey: 'logo-containerd', value: diag.containerd?.version ?? 'N/A' },
    { logoKey: 'logo-docker',     value: diag.docker?.version ?? 'N/A' },
    { logoKey: 'logo-cilium',     value: diag.cilium?.version ?? 'N/A' },
    { logoKey: 'logo-kubernetes', value: diag.kubernetes?.version ?? 'N/A' },
    { logoKey: 'logo-gatewayapi', value: diag.gatewayAPI?.version ?? 'N/A' },
    { logoKey: 'logo-helm',       value: diag.helm?.version ?? 'N/A' },
    { logoKey: 'logo-traefik',    value: diag.traefik?.build?.version ?? 'N/A' },
    { logoKey: 'logo-hlsjs',      value: diag.libraries?.['hls.js']?.version ?? 'N/A' },
    { logoKey: 'logo-p5js',       value: diag.libraries?.['p5.js']?.version ?? 'N/A' }
  ];

  awrWeb.textSize(baseSize);
  awrWeb.fill(255);
  // Force typography to anchor strictly to its true vertical middle axis
  awrWeb.textAlign(awrWeb.RIGHT, awrWeb.CENTER);

  // Measure the widest version string to maintain a rock-solid column channel
  const maxVersionW = softwareEntries.reduce((max, e) => Math.max(max, awrWeb.textWidth(e.value)), 0);

  const rightX = awrWeb.width - margin;
  const valueX = rightX;
  const logoX = rightX - maxVersionW - (boxSize * 2.2);

  let rightY = awrWeb.height - margin - (rowHeight * softwareEntries.length);

  for (const { logoKey, value } of softwareEntries) {
    // Calculate the concrete grid row midpoint coordinate for this row line
    const rowMidpointY = rightY + (rowHeight / 2);

    // Render version text anchored neatly off that center tracking line
    awrWeb.text(value, valueX, rowMidpointY);

    if (logoKey) {
      const img = icons[logoKey];
      if (img && img.width > 0) {
        const scale = Math.min(boxSize / img.width, boxSize / img.height);
        const w = img.width * scale;
        const h = img.height * scale;

        // Center the graphics container perfectly onto the same midpoint line pixel
        const cx = logoX + (boxSize - w) / 2;
        const cy = rowMidpointY - (h / 2);

        awrWeb.push();
        awrWeb.image(img, cx, cy, w, h);
        awrWeb.pop();
      }
    }

    rightY += rowHeight;
  }

  // ====================================================
  // 2. BOTTOM LEFT: STRUCTURAL CLUSTER INFO
  // ====================================================
  const clusterTopology = [
    { target: 'CLUSTER LOAD-BALANCER', value: diag.awroberts?.service?.clusterIP ?? 'N/A', extra: 'Traefik Ingress Routing' },
    { target: 'NODE: awr [amd64]',     value: diag.pods?.web?.ip ?? 'N/A',               extra: '-> awroberts-web-pod' },
    { target: 'NODE: awr-ffmpeg [arm64]', value: diag.pods?.backgroundFfmpeg?.ip ?? 'N/A',  extra: '-> background-ffmpeg-worker' },
  ];

  awrWeb.textAlign(awrWeb.LEFT, awrWeb.TOP);

  const leftX = margin;
  let leftY = awrWeb.height - margin - (rowHeight * clusterTopology.length * 1.5);

  for (const { target, value, extra } of clusterTopology) {
    // Label item header (Dimmed/Clean system-blue accent tint)
    awrWeb.fill(127, 203, 255, 160);
    awrWeb.text(target, leftX, leftY);

    // Live IP structural details mapped out right beneath the header line
    awrWeb.fill(255, 230);
    awrWeb.text(`  ↳ IP: ${value}  (${extra})`, leftX, leftY + (baseSize * 1.1));

    leftY += rowHeight * 1.6;
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
