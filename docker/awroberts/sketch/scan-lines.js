// scan-lines.js — early 90s CRT scan line overlay

import { sampleVideoColumn, updateVideoFrame, getVideoLayerCanvas, getVideoFadeAlpha } from './video.js';

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
const ROLL_SPEED         = 0.25;
const INTENSITY_SPEED    = 0.008;
const BRIGHT_BAND_SPEED  = 0.5;
const BRIGHT_BAND_HEIGHT = 40;
const BRIGHT_BAND_ALPHA  = 18;
const DROPOUT_CHANCE     = 0.005;
const STYLE_BLEND_SPEED  = 0.002; // full oscillation ~52s at 60fps

// Three evenly-spaced x positions sampled for bright-band colour tinting
const NUM_COL_SAMPLES = 3;

// Deterministic per-line hash — stable across frames, avoids per-frame jitter noise
function lineHash(y, seed) {
  const v = Math.sin((y + seed) * 127.1) * 43758.5453;
  return v - Math.floor(v); // 0–1
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

  // Keep the video frame current
  updateVideoFrame();

  const w = scanLayer.width;
  const h = scanLayer.height;

  brightBandY = (brightBandY + BRIGHT_BAND_SPEED) % (h + BRIGHT_BAND_HEIGHT);

  // 0 = original simple style, 1 = full enhanced — slow sine oscillation
  const styleBlend = 0.5 + 0.5 * Math.sin(styleBlendT);

  // Sample columns for bright-band colour tinting
  const cols = [];
  for (let i = 0; i < NUM_COL_SAMPLES; i++) {
    cols.push(sampleVideoColumn(Math.floor(w * (i + 0.5) / NUM_COL_SAMPLES)));
  }
  const colHeight = cols[0] ? cols[0].length / 4 : 0;

  scanLayer.clear();
  scanLayer.push();
  scanLayer.noStroke();

  // Rolling bright band — alpha scales with styleBlend
  const bandTop = brightBandY - BRIGHT_BAND_HEIGHT;

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

  const ctx         = awrScanLines.drawingContext;
  const w           = ctx.canvas.width;
  const h           = ctx.canvas.height;
  const styleBlend  = 0.5 + 0.5 * Math.sin(styleBlendT);

  const videoCanvas = getVideoLayerCanvas();
  const fadeAlpha   = getVideoFadeAlpha(); // 0–1

  if (videoCanvas && fadeAlpha > 0) {
    // Build a clip path made of the lit scan-line strips.
    // The video is drawn only through these strips; the poster shows through the gaps.
    const path = new Path2D();
    for (let y = Math.floor(rollOffset); y < h; y += LINE_SPACING) {
      // Per-frame random dropout — occasional static line (poster bleeds through)
      if (Math.random() < DROPOUT_CHANCE) continue;

      // Stable sub-pixel y jitter, scales with styleBlend
      const jy = y + (lineHash(y, 0) - 0.5) * 0.8 * styleBlend;

      // 1% chance of a 2px-tall strip in enhanced mode
      const lh = (styleBlend > 0.5 && lineHash(y, 100) < 0.01) ? 2 : 1;

      path.rect(0, Math.round(jy), w, lh);
    }

    ctx.save();
    ctx.globalAlpha = fadeAlpha;
    ctx.clip(path);
    ctx.drawImage(videoCanvas, 0, 0, w, h);
    ctx.restore();
  }

  // Bright-band overlay drawn on top, unclipped
  awrScanLines.image(scanLayer, 0, 0);
}

// -----------------------------
// RESIZE
// -----------------------------
export function handleScanLinesResize() {
  if (!scanLayer) return;
  scanLayer.resizeCanvas(awrScanLines.windowWidth, awrScanLines.windowHeight);
}
