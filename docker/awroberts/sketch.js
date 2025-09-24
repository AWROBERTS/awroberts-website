let Font;
const textString = 'info@awroberts.co.uk';

let baseSize = 0;
let noiseSeedFast = [];
let noiseSeedSlow = [];
let phase = [];
let burst = [];
let textBounds = { x: 0, y: 0, width: 0, height: 0 };

function preload() {
  Font = loadFont('/awroberts-media/CURWENFONT.ttf');
}

function setup() {
  const canvas = createCanvas(windowWidth, windowHeight);
  canvas.parent('canvas-container');
  canvas.style('position', 'absolute');
  canvas.style('top', '0');
  canvas.style('left', '0');
  canvas.style('z-index', '10');

  pixelDensity(1);
  noStroke();
  textAlign(LEFT, BASELINE);
  textFont(Font);

  baseSize = Math.min(windowWidth, windowHeight) / 10;

  for (let i = 0; i < textString.length; i++) {
    noiseSeedFast[i] = random(10000);
    noiseSeedSlow[i] = random(10000);
    phase[i] = random(TWO_PI);
    burst[i] = 0;
  }
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  baseSize = Math.min(windowWidth, windowHeight) / 10;
}

function draw() {
  clear();
  fill(255);
  textFont(Font);

  const t = millis() / 1000;
  const maxJitter = 30;

  const sizes = new Array(textString.length);
  const widths = new Array(textString.length);
  let totalWidth = 0;

  for (let i = 0; i < textString.length; i++) {
    const fast = (noise(noiseSeedFast[i] + t * 2.0) * 2 - 1) * 18;
    const wobble = sin(t * 4.0 + phase[i]) * 8;
    const slow = (noise(noiseSeedSlow[i] + t * 0.3) * 2 - 1) * 10;

    if (random() < 0.004) burst[i] = maxJitter;
    burst[i] *= 0.90;

    const delta = constrain(fast + wobble + slow + burst[i] * sin(t * 10 + phase[i]), -maxJitter, maxJitter);
    const sz = baseSize + delta;
    sizes[i] = sz;

    textSize(sz);
    widths[i] = textWidth(textString.charAt(i));
    totalWidth += widths[i];
  }

  const xStart = (width - totalWidth) / 2;
  textSize(baseSize);
  const asc = textAscent();
  const desc = textDescent();
  const margin = 12;
  const minBaseline = asc + margin;
  const maxBaseline = Math.max(asc + margin, height / 2 - desc - margin);
  let baselineY = constrain(height * 0.30, minBaseline, maxBaseline);

  // Update bounding box for interaction
  textBounds.x = xStart;
  textBounds.y = baselineY - baseSize;
  textBounds.width = totalWidth;
  textBounds.height = baseSize * 1.2;

  // Cursor feedback
  if (
    mouseX >= textBounds.x &&
    mouseX <= textBounds.x + textBounds.width &&
    mouseY >= textBounds.y &&
    mouseY <= textBounds.y + textBounds.height
  ) {
    cursor(HAND);
  } else {
    cursor(ARROW);
  }

  let x = xStart;
  for (let i = 0; i < textString.length; i++) {
    const char = textString.charAt(i);
    const yBob = sin(t * 2.2 + phase[i] * 0.7) * baseSize * 0.08
               + (noise(noiseSeedSlow[i] + t * 1.1) - 0.5) * baseSize * 0.06;
    const effectiveBaseline = constrain(baselineY + yBob, minBaseline, maxBaseline);
    const angle = sin(t * 3.5 + phase[i] * 1.3) * 0.06;

    push();
    translate(x, effectiveBaseline);
    rotate(angle);
    textSize(sizes[i]);
    text(char, 0, 0);
    pop();

    x += widths[i];
  }
}

function mousePressed() {
  if (
    mouseX >= textBounds.x &&
    mouseX <= textBounds.x + textBounds.width &&
    mouseY >= textBounds.y &&
    mouseY <= textBounds.y + textBounds.height
  ) {
    window.location.href = 'mailto:info@awroberts.co.uk';
  }
}
