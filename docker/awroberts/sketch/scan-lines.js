// scan-lines.js — early 90s CRT scan line overlay

import { sampleVideoColumn, updateVideoFrame, getVideoLayerCanvas, getVideoFadeAlpha } from './video.js';
import { isMobileDevice } from './utils.js';

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
let scanLayer      = null;
let videoClipLayer = null;
let scanPattern    = null;

let rollOffset   = 0;
let intensityT   = 0;
let brightBandY  = 0;
let styleBlendT  = 0;

const LINE_SPACING       = 4;  // total period (lit + gap)
const LINE_LIT           = 2;  // height of the lit video strip within each period
const ROLL_SPEED         = 0.25;
const INTENSITY_SPEED    = 0.008;
const BRIGHT_BAND_SPEED  = 0.5;
const BRIGHT_BAND_HEIGHT = 40;
const BRIGHT_BAND_ALPHA  = 18;
const STYLE_BLEND_SPEED  = 0.002; // full oscillation ~52s at 60fps

// Three evenly-spaced x positions sampled for horizontal colour variation (desktop only)
const NUM_COL_SAMPLES = 3;

// Deterministic per-line hash — stable across frames
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

// Build a 1×LINE_SPACING tile canvas: first row lit (white), rest transparent.
// Used as a repeating CanvasPattern so the scanline mask is a single fillRect per frame.
function buildScanPattern(ctx) {
  const tile    = document.createElement('canvas');
  tile.width    = 1;
  tile.height   = LINE_SPACING;
  const tCtx    = tile.getContext('2d');
  tCtx.clearRect(0, 0, 1, LINE_SPACING);
  tCtx.fillStyle = 'rgba(255,255,255,1)';
  tCtx.fillRect(0, 0, 1, LINE_LIT); // first LINE_LIT rows = lit strip
  // rows LINE_LIT…(LINE_SPACING-1) remain transparent = dark gap
  return ctx.createPattern(tile, 'repeat');
}

// -----------------------------
// INIT
// -----------------------------
export function initScanLines() {
  scanLayer = awrScanLines.createGraphics(awrScanLines.windowWidth, awrScanLines.windowHeight);
  scanLayer.pixelDensity(1);
  scanLayer.clear();

  // Intermediate layer: video is drawn here and masked to scan strips before compositing
  videoClipLayer = awrScanLines.createGraphics(awrScanLines.windowWidth, awrScanLines.windowHeight);
  videoClipLayer.pixelDensity(1);
  videoClipLayer.clear();

  scanPattern = buildScanPattern(videoClipLayer.drawingContext);

  intensityT  = 0;
  styleBlendT = Math.random() * Math.PI * 2;
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

  updateVideoFrame();

  const w = scanLayer.width;
  const h = scanLayer.height;

  brightBandY = (brightBandY + BRIGHT_BAND_SPEED) % (h + BRIGHT_BAND_HEIGHT);

  const styleBlend = 0.5 + 0.5 * Math.sin(styleBlendT);

  // Sample columns for bright-band colour tinting.
  // Skipped on mobile — getImageData causes GPU stalls on low-power devices.
  let bandR = 255, bandG = 255, bandB = 255;
  if (!isMobileDevice()) {
    const cols = [];
    for (let i = 0; i < NUM_COL_SAMPLES; i++) {
      cols.push(sampleVideoColumn(Math.floor(w * (i + 0.5) / NUM_COL_SAMPLES)));
    }
    const colHeight = cols[0] ? cols[0].length / 4 : 0;
    const [centR, centG, centB] = colRGB(
      cols[Math.floor(NUM_COL_SAMPLES / 2)],
      colHeight,
      brightBandY - BRIGHT_BAND_HEIGHT * 0.5
    );
    bandR = Math.round(255 * 0.7 + centR * 0.3);
    bandG = Math.round(255 * 0.7 + centG * 0.3);
    bandB = Math.round(255 * 0.7 + centB * 0.3);
  }

  scanLayer.clear();
  scanLayer.push();
  scanLayer.noStroke();

  // Rolling bright band
  const bandTop = brightBandY - BRIGHT_BAND_HEIGHT;
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
  if (!scanLayer || !videoClipLayer || !scanPattern) return;

  const videoCanvas = getVideoLayerCanvas();
  const fadeAlpha   = getVideoFadeAlpha(); // 0–1

  if (videoCanvas && fadeAlpha > 0) {
    const clipCtx = videoClipLayer.drawingContext;
    const w = clipCtx.canvas.width;
    const h = clipCtx.canvas.height;

    // 1. Draw full video frame onto the intermediate layer
    clipCtx.clearRect(0, 0, w, h);
    clipCtx.globalAlpha = fadeAlpha;
    clipCtx.drawImage(videoCanvas, 0, 0, w, h);
    clipCtx.globalAlpha = 1;

    // 2. Punch out the gap rows using the scrolling tile pattern.
    //    destination-in keeps only pixels where the pattern is opaque (lit rows).
    //    rollOffset shifts the pattern each frame, creating the scrolling motion.
    scanPattern.setTransform(new DOMMatrix().translateSelf(0, rollOffset));
    clipCtx.globalCompositeOperation = 'destination-in';
    clipCtx.fillStyle = scanPattern;
    clipCtx.fillRect(0, 0, w, h);
    clipCtx.globalCompositeOperation = 'source-over';

    // 3. Composite the masked video onto the main canvas (poster shows through transparent gaps)
    awrScanLines.image(videoClipLayer, 0, 0);
  }

  // Bright-band overlay, unclipped
  awrScanLines.image(scanLayer, 0, 0);
}

// -----------------------------
// RESIZE
// -----------------------------
export function handleScanLinesResize() {
  if (!scanLayer) return;
  scanLayer.resizeCanvas(awrScanLines.windowWidth, awrScanLines.windowHeight);
  if (videoClipLayer) {
    videoClipLayer.resizeCanvas(awrScanLines.windowWidth, awrScanLines.windowHeight);
    // Recreate pattern after resize in case the context was replaced
    scanPattern = buildScanPattern(videoClipLayer.drawingContext);
  }
}
