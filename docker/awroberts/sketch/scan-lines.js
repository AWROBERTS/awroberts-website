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
let scanLayer   = null;
let rollOffset  = 0;
let intensityT  = 0;
let brightBandY = 0;

const LINE_SPACING       = 2;
const LINE_ALPHA_MIN     = 40;
const LINE_ALPHA_MAX     = 120;
const ROLL_SPEED         = 0.25;
const INTENSITY_SPEED    = 0.008;
const BRIGHT_BAND_SPEED  = 0.5;
const BRIGHT_BAND_HEIGHT = 40;
const BRIGHT_BAND_ALPHA  = 18;
const DROPOUT_CHANCE     = 0.005;

// Deterministic per-line hash — stable across frames, avoids per-frame jitter noise
function lineHash(y, seed) {
  const v = Math.sin((y + seed) * 127.1) * 43758.5453;
  return v - Math.floor(v); // 0–1
}

// -----------------------------
// INIT
// -----------------------------
export function initScanLines() {
  scanLayer = awrScanLines.createGraphics(awrScanLines.windowWidth, awrScanLines.windowHeight);
  scanLayer.pixelDensity(1);
  scanLayer.clear();
  intensityT  = 0;
  brightBandY = Math.random() * (awrScanLines.windowHeight + BRIGHT_BAND_HEIGHT);
}

// -----------------------------
// UPDATE
// -----------------------------
export function updateScanLines() {
  if (!scanLayer) return;

  rollOffset  = (rollOffset + ROLL_SPEED) % LINE_SPACING;
  intensityT += INTENSITY_SPEED;

  const w = scanLayer.width;
  const h = scanLayer.height;

  brightBandY = (brightBandY + BRIGHT_BAND_SPEED) % (h + BRIGHT_BAND_HEIGHT);

  scanLayer.clear();
  scanLayer.push();
  scanLayer.noStroke();

  // Shared base intensity — slow sinusoidal cycle using two frequencies
  const baseIntensity = 0.5 + 0.5 * Math.sin(intensityT) * Math.sin(intensityT * 0.37);

  for (let y = Math.floor(rollOffset); y < h; y += LINE_SPACING) {
    // Line dropout — occasional missing line simulating phosphor flicker
    if (Math.random() < DROPOUT_CHANCE) continue;

    // Stable y jitter — deterministic per line position so lines don't jiggle each frame
    const jy = y + (lineHash(y, 0) - 0.5) * 0.8;

    // Per-line independent intensity — each line has its own phase offset
    const linePhase = intensityT + y * 0.03;
    const lineIntensity = 0.5 + 0.5 * Math.sin(linePhase) * Math.sin(linePhase * 0.37);
    const combinedIntensity = (baseIntensity + lineIntensity) * 0.5;

    const flicker = (Math.random() - 0.5) * 12;
    const lineAlpha = LINE_ALPHA_MIN + (LINE_ALPHA_MAX - LINE_ALPHA_MIN) * combinedIntensity + flicker;

    // Stable line height — 5% chance of a 2px line
    const lh = lineHash(y, 100) < 0.05 ? 2 : 1;

    // Stable horizontal micro-jitter — ±1px x offset per line
    const xOff = Math.round((lineHash(y, 200) - 0.5) * 2);

    scanLayer.fill(0, 0, 0, lineAlpha);
    scanLayer.rect(xOff, jy, w, lh);
  }

  // Rolling bright band — subtle lighter stripe drifting down the screen
  const bandTop = brightBandY - BRIGHT_BAND_HEIGHT;
  for (let i = 0; i < BRIGHT_BAND_HEIGHT; i++) {
    const lineY = bandTop + i;
    if (lineY < 0 || lineY >= h) continue;
    const dist = Math.abs(i - BRIGHT_BAND_HEIGHT * 0.5) / (BRIGHT_BAND_HEIGHT * 0.5);
    const bandAlpha = BRIGHT_BAND_ALPHA * (1 - dist * dist);
    if (bandAlpha < 1) continue;
    scanLayer.fill(255, 255, 255, bandAlpha);
    scanLayer.rect(0, lineY, w, 1);
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
}
