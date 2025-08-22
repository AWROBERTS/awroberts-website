// Static text in the top half.
// Each letter ripples "3x crazier" via multiple modulations:
// - Fast Perlin noise
// - Sine wave wobble with per-letter phase
// - Slow Perlin drift
// - Occasional burst spikes with decay
// Plus small vertical bob and rotation wobble for extra liveliness.

let Font;
const textString = 'info@awroberts.co.uk';

let baseSize = 0;
let noiseSeedFast = [];
let noiseSeedSlow = [];
let phase = [];
let burst = [];

function preload() {
  Font = loadFont('/awroberts-media/CURWENFONT.ttf');
}

function setup() {
  const canvas = createCanvas(windowWidth, windowHeight);
  canvas.parent('canvas-container');
  pixelDensity(1);
  noStroke();
  textAlign(LEFT, BASELINE);
  textFont(Font);

  baseSize = Math.min(windowWidth, windowHeight) / 10;

  noiseSeedFast = [];
  noiseSeedSlow = [];
  phase = [];
  burst = [];
  for (let i = 0; i < textString.length; i++) {
    noiseSeedFast[i] = random(10000);
    noiseSeedSlow[i] = random(10000);
    phase[i] = random(TWO_PI);
    burst[i] = 0; // burst amplitude, decays over time
  }
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  baseSize = Math.min(windowWidth, windowHeight) / 10;
}

function draw() {
  clear();
  fill(255);

  const t = millis() / 1000;

  // 3x size jitter range (from +/- 10 to +/- 30 px)
  const maxJitter = 30;

  // Prepare per-letter size and width to center the string
  const sizes = new Array(textString.length);
  const widths = new Array(textString.length);

  // Compute sizes and widths first
  let totalWidth = 0;
  for (let i = 0; i < textString.length; i++) {
    // Multiple modulation sources:
    // Fast noise (jittery but smooth)
    const fast = (noise(noiseSeedFast[i] + t * 2.0) * 2 - 1) * 18;

    // Sine wobble with unique phase per letter
    const wobble = sin(t * 4.0 + phase[i]) * 8;

    // Slow drift noise (bigger, slower movement)
    const slow = (noise(noiseSeedSlow[i] + t * 0.3) * 2 - 1) * 10;

    // Occasional spike (burst) that decays
    if (random() < 0.004) {
      // random chance to trigger a spike
      burst[i] = maxJitter; // kick to full range
    }
    // exponential decay for the burst
    burst[i] *= 0.90;

    // Combine and clamp to +/- maxJitter
    const delta = constrain(fast + wobble + slow + burst[i] * sin(t * 10 + phase[i]), -maxJitter, maxJitter);

    const sz = baseSize + delta;
    sizes[i] = sz;

    textSize(sz);
    widths[i] = textWidth(textString.charAt(i));
    totalWidth += widths[i];
  }

  // Horizontal centering
  const xStart = (width - totalWidth) / 2;

  // Keep text in top half. Choose a steady baseline near 30% height.
  textSize(baseSize);
  const asc = textAscent();
  const desc = textDescent();
  const margin = 12;
  const minBaseline = asc + margin;
  const maxBaseline = Math.max(asc + margin, height / 2 - desc - margin);
  let baselineY = constrain(height * 0.30, minBaseline, maxBaseline);

  // Draw pass with extra "crazy" but readable transforms:
  // small vertical bob and tiny rotation wobble per letter
  let x = xStart;
  for (let i = 0; i < textString.length; i++) {
    const char = textString.charAt(i);

    // Vertical bob: keep subtle relative to baseSize to preserve legibility
    const yBob = sin(t * 2.2 + phase[i] * 0.7) * baseSize * 0.08
               + (noise(noiseSeedSlow[i] + t * 1.1) - 0.5) * baseSize * 0.06;

    // Ensure we remain within the top half by clamping effective baseline
    const effectiveBaseline = constrain(baselineY + yBob, minBaseline, maxBaseline);

    // Small rotation wobble
    const angle = sin(t * 3.5 + phase[i] * 1.3) * 0.06; // ~3.4 degrees max

    // Render
    push();
    translate(x, effectiveBaseline);
    rotate(angle);
    textSize(sizes[i]);
    text(char, 0, 0);
    pop();

    x += widths[i];
  }
}