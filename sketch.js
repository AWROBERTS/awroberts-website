// Static text in the top half, each letter ripples its size by +/- 10px semi-randomly.

let Font;
const textString = 'info@awroberts.co.uk';

let baseSize = 0;
let letterNoise = [];

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

  // Base size relative to viewport
  baseSize = Math.min(windowWidth, windowHeight) / 10;

  // Per-letter noise seeds
  letterNoise = [];
  for (let i = 0; i < textString.length; i++) {
    letterNoise[i] = random(10000);
  }
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  baseSize = Math.min(windowWidth, windowHeight) / 10;
}

function draw() {
  clear();
  fill(255);

  const t = millis() * 0.0006; // time factor for smooth variation
  const maxJitter = 10;        // +/- 10px around base size

  // Compute current size and width of each character to center the text
  const sizes = new Array(textString.length);
  const widths = new Array(textString.length);

  // First pass: measure widths at current per-letter sizes
  let totalWidth = 0;
  for (let i = 0; i < textString.length; i++) {
    // Semi-random smooth jitter using perlin noise
    const n = noise(letterNoise[i] + t); // 0..1
    const delta = map(n, 0, 1, -maxJitter, maxJitter);
    const sz = baseSize + delta;

    sizes[i] = sz;
    textSize(sz);
    const w = textWidth(textString.charAt(i));
    widths[i] = w;
    totalWidth += w;
  }

  // Position in the top half, horizontally centered
  const xStart = (width - totalWidth) / 2;
  // Choose a baseline safely in the top half
  // Use the median ascent/descent by sampling at baseSize
  textSize(baseSize);
  const ascent = textAscent();
  const descent = textDescent();
  const minBaseline = ascent + 10;
  const maxBaseline = Math.max(ascent + 10, height / 2 - descent - 10);
  const baselineY = constrain(height * 0.3, minBaseline, maxBaseline);

  // Second pass: draw with the same sizes
  let x = xStart;
  for (let i = 0; i < textString.length; i++) {
    textSize(sizes[i]);
    text(textString.charAt(i), x, baselineY);
    x += widths[i];
  }
}