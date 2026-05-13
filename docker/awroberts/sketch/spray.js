// spray.js

// -----------------------------
// INTERNAL P5 INSTANCE
// -----------------------------
let awrSpray = null;

export function bindSprayP5(p) {
  awrSpray = p;
}

// -----------------------------
// STATE
// -----------------------------
let sprayLayer   = null;
let columnAccum  = null;
let drips        = [];
let sampleColor  = null;

const SPRAY_RADIUS        = 50;
const PARTICLES_PER_FRAME = 15;
const DRIP_THRESHOLD      = 40;
const DRIP_GRAVITY        = 0.35;
const DRIP_MAX_SPEED      = 16;

// -----------------------------
// INIT
// -----------------------------
export function initSpray(colorSampler) {
  sampleColor = colorSampler;

  sprayLayer = awrSpray.createGraphics(awrSpray.windowWidth, awrSpray.windowHeight);
  sprayLayer.pixelDensity(1);
  sprayLayer.clear();

  columnAccum = new Float32Array(awrSpray.windowWidth);
  drips = [];
}

// -----------------------------
// UPDATE
// -----------------------------
export function updateSpray(mx, my, isPressed) {
  if (!sprayLayer) return;

  if (isPressed) {
    const [br, bg, bb] = sampleColor(mx, my);

    for (let i = 0; i < PARTICLES_PER_FRAME; i++) {
      const angle  = Math.random() * Math.PI * 2;
      const dist   = Math.random() * SPRAY_RADIUS;
      const px     = mx + Math.cos(angle) * dist;
      const py     = my + Math.sin(angle) * dist;
      const size   = 5 + Math.random() * 10;
      const jitter = () => Math.floor((Math.random() - 0.5) * 20);
      const alpha  = 80 + Math.random() * 80;

      sprayLayer.push();
      sprayLayer.noStroke();
      sprayLayer.fill(
        Math.min(255, Math.max(0, br + jitter())),
        Math.min(255, Math.max(0, bg + jitter())),
        Math.min(255, Math.max(0, bb + jitter())),
        alpha
      );
      sprayLayer.ellipse(px, py, size, size);
      sprayLayer.pop();

      const col = Math.floor(awrSpray.constrain(px, 0, columnAccum.length - 1));
      columnAccum[col] += size;
    }
  }

  // Spawn drips from columns that have accumulated enough paint
  for (let col = 0; col < columnAccum.length; col++) {
    if (columnAccum[col] > DRIP_THRESHOLD) {
      drips.push({
        x:      col,
        y:      my,
        vy:     1,
        width:  8 + Math.random() * 10,
        length: 10
      });
      columnAccum[col] = 0;
    }
  }

  // Update drip physics only — drawing happens in drawSpray with live colour
  drips = drips.filter(drip => {
    drip.vy     = Math.min(drip.vy + DRIP_GRAVITY, DRIP_MAX_SPEED);
    drip.y     += drip.vy;
    drip.length = Math.min(drip.vy * 4, 60);

    if (drip.y >= awrSpray.height) {
      // Leave a pool at the bottom using live colour
      const [pr, pg, pb] = sampleColor(drip.x, awrSpray.height - 2);
      sprayLayer.push();
      sprayLayer.noStroke();
      sprayLayer.fill(pr, pg, pb, 200);
      sprayLayer.ellipse(drip.x, awrSpray.height - 2, drip.width * 2.5, drip.width);
      sprayLayer.pop();
      return false;
    }

    return true;
  });
}

// -----------------------------
// DRAW
// -----------------------------
export function drawSpray() {
  if (!sprayLayer) return;

  // Draw the accumulated spray mist layer
  awrSpray.image(sprayLayer, 0, 0);

  // Draw drips fresh every frame with live-sampled video colour
  if (drips.length === 0) return;
  awrSpray.push();
  awrSpray.noStroke();
  for (const drip of drips) {
    const [r, g, b] = sampleColor(drip.x, drip.y);

    // Drip body — tall rounded rect
    awrSpray.fill(r, g, b, 240);
    awrSpray.rect(
      drip.x - drip.width / 2,
      drip.y - drip.length,
      drip.width,
      drip.length,
      drip.width / 2
    );

    // Teardrop tip at the bottom
    awrSpray.ellipse(drip.x, drip.y, drip.width * 1.4, drip.width * 1.4);
  }
  awrSpray.pop();
}

// -----------------------------
// RESIZE
// -----------------------------
export function handleSprayResize() {
  if (!sprayLayer) return;
  sprayLayer.resizeCanvas(awrSpray.windowWidth, awrSpray.windowHeight);
  columnAccum = new Float32Array(awrSpray.windowWidth);
  drips = [];
}
