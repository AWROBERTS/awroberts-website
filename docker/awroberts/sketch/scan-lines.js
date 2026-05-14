// scan-lines.js — early 90s CRT scan line overlay

// -----------------------------
// INTERNAL P5 INSTANCE
// -----------------------------
let awrScanLines = null;

export function bindScanLinesP5(p) {
  awrScanLines = p;
}

// -----------------------------
// STATE
// -----------------------------
let scanLayer  = null;
let rollOffset = 0;
let glitchBands = [];

const LINE_SPACING   = 3;    // px between each dark scan line
const LINE_ALPHA     = 45;   // base darkness of each scan line
const ROLL_SPEED     = 0.25; // px/frame — very slow vertical drift

// -----------------------------
// INIT
// -----------------------------
export function initScanLines() {
  scanLayer = awrScanLines.createGraphics(awrScanLines.windowWidth, awrScanLines.windowHeight);
  scanLayer.pixelDensity(1);
  scanLayer.clear();
  glitchBands = [];
}

// -----------------------------
// UPDATE
// -----------------------------
export function updateScanLines(mx, my, isPressed) {
  if (!scanLayer) return;

  rollOffset = (rollOffset + ROLL_SPEED) % LINE_SPACING;

  // Occasionally spawn a rolling glitch band
  if (Math.random() < 0.008) {
    glitchBands.push({
      y:     Math.random() * scanLayer.height,
      h:     2 + Math.floor(Math.random() * 6),
      alpha: 60 + Math.random() * 80,
      life:  4 + Math.floor(Math.random() * 10)
    });
  }

  glitchBands = glitchBands.filter(g => --g.life > 0);

  scanLayer.clear();
  scanLayer.push();
  scanLayer.noStroke();

  const w = scanLayer.width;
  const h = scanLayer.height;

  // Regular scan lines — dark horizontal bands every LINE_SPACING px
  for (let y = Math.floor(rollOffset); y < h; y += LINE_SPACING) {
    const flicker = (Math.random() - 0.5) * 8;
    scanLayer.fill(0, 0, 0, LINE_ALPHA + flicker);
    scanLayer.rect(0, y, w, 1);
  }

  // Glitch bands — brief bright horizontal flashes
  for (const g of glitchBands) {
    const t = g.life / 10;
    scanLayer.fill(255, 255, 255, g.alpha * t);
    scanLayer.rect(0, g.y, w, g.h);
  }

  scanLayer.pop();
}

// -----------------------------
// DRAW
// -----------------------------
export function drawScanLines() {
  if (!scanLayer) return;
  awrScanLines.image(scanLayer, 0, 0);
}

// -----------------------------
// RESIZE
// -----------------------------
export function handleScanLinesResize() {
  if (!scanLayer) return;
  scanLayer.resizeCanvas(awrScanLines.windowWidth, awrScanLines.windowHeight);
  glitchBands = [];
}
