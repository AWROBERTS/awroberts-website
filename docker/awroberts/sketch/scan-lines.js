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
let glitchBands = [];
let intensityT  = 0; // drives the fade in/out cycle
let burstCooldown = 0; // frames until next burst is allowed

const LINE_SPACING    = 2;    // px between each dark scan line (denser)
const LINE_ALPHA_MIN  = 40;   // darkest the lines get at low intensity
const LINE_ALPHA_MAX  = 120;  // darkest the lines get at peak intensity
const LINE_HEIGHT     = 1;    // height of each scan line in px
const ROLL_SPEED      = 0.25; // px/frame — very slow vertical drift
const INTENSITY_SPEED = 0.008; // speed of the fade in/out cycle
const MAX_BANDS       = 30;   // cap to avoid runaway spawning

// -----------------------------
// INIT
// -----------------------------
export function initScanLines() {
  scanLayer = awrScanLines.createGraphics(awrScanLines.windowWidth, awrScanLines.windowHeight);
  scanLayer.pixelDensity(1);
  scanLayer.clear();
  glitchBands = [];
  intensityT = 0;
}

// -----------------------------
// UPDATE
// -----------------------------
export function updateScanLines(mx, my, isPressed) {
  if (!scanLayer) return;

  rollOffset  = (rollOffset + ROLL_SPEED) % LINE_SPACING;
  intensityT += INTENSITY_SPEED;
  if (burstCooldown > 0) burstCooldown--;

  // Slow sinusoidal intensity — combines two frequencies for an organic feel
  const intensity = 0.5 + 0.5 * Math.sin(intensityT) * Math.sin(intensityT * 0.37);
  const lineAlpha = LINE_ALPHA_MIN + (LINE_ALPHA_MAX - LINE_ALPHA_MIN) * intensity;

  // Trickle: spawn individual bands continuously at a higher base rate
  const trickleChance = 0.035 + intensity * 0.06;
  const trickleCount  = Math.random() < 0.3 ? 2 : 1; // occasionally double-spawn
  if (glitchBands.length < MAX_BANDS && Math.random() < trickleChance) {
    for (let i = 0; i < trickleCount; i++) {
      glitchBands.push(makeWhiteBand(scanLayer.height));
    }
  }

  // Burst: every so often fire a cluster of bands within a narrow vertical range
  if (burstCooldown === 0 && Math.random() < 0.012 + intensity * 0.025) {
    const clusterY   = Math.random() * scanLayer.height;
    const clusterSpread = 20 + Math.random() * 60;
    const count = 3 + Math.floor(Math.random() * 6);
    for (let i = 0; i < count && glitchBands.length < MAX_BANDS; i++) {
      const band = makeWhiteBand(scanLayer.height);
      band.y = clusterY + (Math.random() - 0.5) * clusterSpread;
      band.h = 1 + Math.floor(Math.random() * 5); // thinner within a burst cluster
      glitchBands.push(band);
    }
    burstCooldown = 8 + Math.floor(Math.random() * 20);
  }

  // Advance each band: drift downward at its own speed, fade out over its lifetime
  for (const g of glitchBands) {
    g.y   += g.speed;
    g.life--;
  }
  glitchBands = glitchBands.filter(g => g.life > 0);

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

  // Glitch bands — brief bright horizontal flashes
  for (const g of glitchBands) {
    const t = g.life / g.maxLife; // normalised 0→1 over the band's own lifetime
    scanLayer.fill(255, 255, 255, g.alpha * t);
    scanLayer.rect(0, g.y, w, g.h);
  }

  scanLayer.pop();
}

// Factory — centralises the randomness for a single white band
function makeWhiteBand(canvasHeight) {
  const maxLife = 3 + Math.floor(Math.random() * 18);
  return {
    y:       Math.random() * canvasHeight,
    h:       1 + Math.floor(Math.random() * 12),
    alpha:   100 + Math.random() * 155,
    life:    maxLife,
    maxLife,
    speed:   (Math.random() - 0.3) * 1.5, // mostly downward drift, occasionally still/up
  };
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
