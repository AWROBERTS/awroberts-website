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
const PARTICLES_PER_FRAME = 20;
const DRIP_THRESHOLD      = 80;
const DRIP_GRAVITY        = 0.4;
const DRIP_MAX_SPEED      = 18;

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
      const size   = 2 + Math.random() * 6;
      const jitter = () => Math.floor((Math.random() - 0.5) * 30);
      const alpha  = 30 + Math.random() * 40;

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
      const [br, bg, bb] = sampleColor(col, my);
      drips.push({
        x:      col,
        y:      my,
        vy:     1,
        r:      br,
        g:      bg,
        b:      bb,
        width:  4 + Math.random() * 6,
        length: 8
      });
      columnAccum[col] = 0;
    }
  }

  // Update and draw drips
  drips = drips.filter(drip => {
    drip.vy   = Math.min(drip.vy + DRIP_GRAVITY, DRIP_MAX_SPEED);
    drip.y   += drip.vy;
    drip.length = Math.min(drip.vy * 3, 40);

    sprayLayer.push();
    sprayLayer.noStroke();
    sprayLayer.fill(drip.r, drip.g, drip.b, 200);
    sprayLayer.rect(
      drip.x - drip.width / 2,
      drip.y - drip.length,
      drip.width,
      drip.length,
      drip.width / 2
    );
    sprayLayer.pop();

    if (drip.y >= awrSpray.height) {
      // Leave a pool at the bottom
      sprayLayer.push();
      sprayLayer.noStroke();
      sprayLayer.fill(drip.r, drip.g, drip.b, 180);
      sprayLayer.ellipse(drip.x, awrSpray.height - 2, drip.width * 2, drip.width);
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
  awrSpray.image(sprayLayer, 0, 0);
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
