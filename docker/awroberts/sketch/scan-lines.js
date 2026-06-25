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

// Three evenly-spaced x positions sampled for horizontal colour variation
const NUM_COL_SAMPLES = 3;

// Deterministic per-line hash — stable across frames, avoids per-frame jitter noise
function lineHash(y, seed) {
  const v = Math.sin((y + seed) * 127.1) * 43758.5453;
  return v - Math.floor(v); // 0–1
}

// Linearly interpolate between two values
function lerp(a, b, t) {
  return a + (b - a) * t;
}

// Sample video RGB at a given column and row from a Uint8ClampedArray column buffer
function colRGB(colData, colHeight, y) {
  if (!colData || colHeight === 0) return [0, 0, 0];
  const vidY = Math.min(Math.max(Math.floor(y), 0), colHeight - 1);
  const idx  = vidY * 4;
  return [colData[idx], colData[idx + 1], colData[idx + 2]];
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

  // Sample three vertical columns for horizontal colour variation —
  // three getImageData calls cover left, centre, right of the frame.
  const cols = [];
  for (let i = 0; i < NUM_COL_SAMPLES; i++) {
    cols.push(sampleVideoColumn(Math.floor(w * (i + 0.5) / NUM_COL_SAMPLES)));
  }
  const colHeight = cols[0] ? cols[0].length / 4 : 0;

  // Segment width for horizontal splits
  const segW = Math.floor(w / NUM_COL_SAMPLES);

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

    // Stable line height — 1% chance of 2px, only in enhanced mode
    const lh = (styleBlend > 0.5 && lineHash(y, 100) < 0.01) ? 2 : 1;

    // Stable horizontal micro-jitter — ±1px, scales with styleBlend
    const xOff = Math.round((lineHash(y, 200) - 0.5) * 2 * styleBlend);

    // Draw scan line in NUM_COL_SAMPLES segments, each tinted with the local video colour.
    // Brighter video = slightly more opaque scan line (higher contrast of lit phosphors vs dark gap).
    for (let si = 0; si < NUM_COL_SAMPLES; si++) {
      const segX = si * segW + xOff;
      const segWidth = si === NUM_COL_SAMPLES - 1 ? w - si * segW : segW;

      const [vR, vG, vB] = colRGB(cols[si], colHeight, jy);

      // Video brightness modulation (scales with styleBlend)
      const brightness  = (vR + vG + vB) / 3;
      const brightnessAlpha = lineAlpha * (1 + (brightness / 255) * 0.25 * styleBlend);

      // Dark gap: tinted with video colour at 15% instead of pure black
      // — makes the scan lines feel like shadowed phosphors rather than a separate overlay
      const tint = 0.15 * styleBlend;
      scanLayer.fill(vR * tint, vG * tint, vB * tint, brightnessAlpha);
      scanLayer.rect(segX, jy, segWidth, lh);

      // Phosphor edge glow — subtle video-coloured bleed at the top edge of the dark band,
      // simulating adjacent lit phosphors leaking light into the gap
      const glowAlpha = brightnessAlpha * 0.18 * styleBlend;
      if (glowAlpha >= 1 && jy - 1 >= 0) {
        scanLayer.fill(vR, vG, vB, glowAlpha);
        scanLayer.rect(segX, jy - 1, segWidth, 1);
      }
    }
  }

  // Rolling bright band — alpha scales with styleBlend (invisible in original mode)
  const bandTop = brightBandY - BRIGHT_BAND_HEIGHT;

  // Tint the band toward the video colour at its centre position
  const [centR, centG, centB] = colRGB(
    cols[Math.floor(NUM_COL_SAMPLES / 2)],
    colHeight,
    brightBandY - BRIGHT_BAND_HEIGHT * 0.5
  );
  const bandR = Math.round(255 * 0.7 + centR * 0.3);
  const bandG = Math.round(255 * 0.7 + centG * 0.3);
  const bandB = Math.round(255 * 0.7 + centB * 0.3);

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
