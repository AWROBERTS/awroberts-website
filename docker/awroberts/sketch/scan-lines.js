// scan-lines.js — early 90s CRT scan line overlay

import { sampleVideoColumn } from './video.js';

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
let scanLayer    = null;
let rollOffset   = 0;
let intensityT   = 0;
let brightBandY  = 0;
let styleBlendT  = 0;

const LINE_SPACING       = 2;
const LINE_ALPHA_MIN     = 40;
const LINE_ALPHA_MAX     = 120;
const ROLL_SPEED         = 0.25;
const INTENSITY_SPEED    = 0.008;
const BRIGHT_BAND_SPEED  = 0.5;
const BRIGHT_BAND_HEIGHT = 40;
const BRIGHT_BAND_ALPHA  = 18;
const DROPOUT_CHANCE     = 0.005;
const STYLE_BLEND_SPEED  = 0.002; // full oscillation ~52s at 60fps

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
  styleBlendT = Math.random() * Math.PI * 2; // random start phase
  brightBandY = Math.random() * (awrScanLines.windowHeight + BRIGHT_BAND_HEIGHT);
}

// -----------------------------
// UPDATE
// -----------------------------
export function updateScanLines() {
  if (!scanLayer) return;

  rollOffset   = (rollOffset + ROLL_SPEED) % LINE_SPACING;
  intensityT  += INTENSITY_SPEED;
  styleBlendT += STYLE_BLEND_SPEED;

  const w = scanLayer.width;
  const h = scanLayer.height;

  brightBandY = (brightBandY + BRIGHT_BAND_SPEED) % (h + BRIGHT_BAND_HEIGHT);

  // 0 = original simple style, 1 = full enhanced — slow sine oscillation
  const styleBlend = 0.5 + 0.5 * Math.sin(styleBlendT);

  // Sample video column once per frame — one getImageData call for all scan lines
  const colData   = sampleVideoColumn(Math.floor(w / 2));
  const colHeight = colData ? colData.length / 4 : 0;

  scanLayer.clear();
  scanLayer.push();
  scanLayer.noStroke();

  // Shared base intensity — slow sinusoidal cycle using two frequencies
  const baseIntensity = 0.5 + 0.5 * Math.sin(intensityT) * Math.sin(intensityT * 0.37);

  for (let y = Math.floor(rollOffset); y < h; y += LINE_SPACING) {
    // Line dropout — occasional missing line simulating phosphor flicker
    if (Math.random() < DROPOUT_CHANCE) continue;

    // Stable y jitter — scales with styleBlend (none at 0, full at 1)
    const jy = y + (lineHash(y, 0) - 0.5) * 0.8 * styleBlend;

    // Per-line intensity — blends from global-only toward per-line as styleBlend increases
    const linePhase     = intensityT + y * 0.03;
    const lineIntensity = 0.5 + 0.5 * Math.sin(linePhase) * Math.sin(linePhase * 0.37);
    const combinedIntensity = baseIntensity * (1 - styleBlend)
                            + ((baseIntensity + lineIntensity) * 0.5) * styleBlend;

    const flicker = (Math.random() - 0.5) * 12;
    let lineAlpha = LINE_ALPHA_MIN + (LINE_ALPHA_MAX - LINE_ALPHA_MIN) * combinedIntensity + flicker;

    // Video brightness modulation — brighter video = slightly more opaque scan lines,
    // simulating the higher contrast of lit phosphors against dark gaps.
    // Effect scales with styleBlend so original mode is unaffected.
    if (colData && colHeight > 0) {
      const vidY = Math.min(Math.max(Math.floor(jy), 0), colHeight - 1);
      const idx  = vidY * 4;
      const brightness = (colData[idx] + colData[idx + 1] + colData[idx + 2]) / 3;
      lineAlpha *= (1 + (brightness / 255) * 0.25 * styleBlend);
    }

    // Stable line height — 1% chance of 2px, only in enhanced mode
    const lh = (styleBlend > 0.5 && lineHash(y, 100) < 0.01) ? 2 : 1;

    // Stable horizontal micro-jitter — ±1px, scales with styleBlend
    const xOff = Math.round((lineHash(y, 200) - 0.5) * 2 * styleBlend);

    scanLayer.fill(0, 0, 0, lineAlpha);
    scanLayer.rect(xOff, jy, w, lh);
  }

  // Rolling bright band — alpha scales with styleBlend (invisible in original mode)
  const bandTop = brightBandY - BRIGHT_BAND_HEIGHT;

  // Tint the band toward the video color at its centre position
  let bandR = 255, bandG = 255, bandB = 255;
  if (colData && colHeight > 0) {
    const bandCenterY = Math.min(Math.max(Math.floor(brightBandY - BRIGHT_BAND_HEIGHT * 0.5), 0), colHeight - 1);
    const idx = bandCenterY * 4;
    // 70% white + 30% video colour so the band picks up the scene's hue
    bandR = Math.round(255 * 0.7 + colData[idx]     * 0.3);
    bandG = Math.round(255 * 0.7 + colData[idx + 1] * 0.3);
    bandB = Math.round(255 * 0.7 + colData[idx + 2] * 0.3);
  }

  for (let i = 0; i < BRIGHT_BAND_HEIGHT; i++) {
    const lineY = bandTop + i;
    if (lineY < 0 || lineY >= h) continue;
    const dist      = Math.abs(i - BRIGHT_BAND_HEIGHT * 0.5) / (BRIGHT_BAND_HEIGHT * 0.5);
    const bandAlpha = BRIGHT_BAND_ALPHA * styleBlend * (1 - dist * dist);
    if (bandAlpha < 1) continue;
    scanLayer.fill(bandR, bandG, bandB, bandAlpha);
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
