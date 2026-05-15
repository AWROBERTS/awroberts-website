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
let intensityT  = 0; // drives the fade in/out cycle

const LINE_SPACING    = 2;    // px between each dark scan line (denser)
const LINE_ALPHA_MIN  = 40;   // darkest the lines get at low intensity
const LINE_ALPHA_MAX  = 120;  // darkest the lines get at peak intensity
const LINE_HEIGHT     = 1;    // height of each scan line in px
const ROLL_SPEED      = 0.25; // px/frame — very slow vertical drift
const INTENSITY_SPEED = 0.008; // speed of the fade in/out cycle

// -----------------------------
// INIT
// -----------------------------
export function initScanLines() {
  scanLayer = awrScanLines.createGraphics(awrScanLines.windowWidth, awrScanLines.windowHeight);
  scanLayer.pixelDensity(1);
  scanLayer.clear();
  intensityT = 0;
}

// -----------------------------
// UPDATE
// -----------------------------
export function updateScanLines() {
  if (!scanLayer) return;

  rollOffset  = (rollOffset + ROLL_SPEED) % LINE_SPACING;
  intensityT += INTENSITY_SPEED;

  // Slow sinusoidal intensity — combines two frequencies for an organic feel
  const intensity = 0.5 + 0.5 * Math.sin(intensityT) * Math.sin(intensityT * 0.37);
  const lineAlpha = LINE_ALPHA_MIN + (LINE_ALPHA_MAX - LINE_ALPHA_MIN) * intensity;

  scanLayer.clear();
  scanLayer.push();
  scanLayer.noStroke();

  const w = scanLayer.width;
  const h = scanLayer.height;

  // Regular scan lines — dark horizontal bands every LINE_SPACING px
  for (let y = Math.floor(rollOffset); y < h; y += LINE_SPACING) {
    const flicker = (Math.random() - 0.5) * 12;
    scanLayer.fill(0, 0, 0, lineAlpha + flicker);
    scanLayer.rect(0, y, w, LINE_HEIGHT);
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
