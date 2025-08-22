let Font;
const textString = 'info@awroberts.co.uk';

let posX = [];
let posY = [];
let velX = [];
let velY = [];
let charW = [];
let ascent = 0;
let descent = 0;

function preload() {
  Font = loadFont('/awroberts-media/CURWENFONT.ttf');
}

function setup() {
  const canvas = createCanvas(windowWidth, windowHeight);
  canvas.parent('canvas-container');
  pixelDensity(1);
  noStroke();
  textAlign(LEFT, BASELINE);
  initLayout();
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  initLayout(true);
}

function initLayout(keepPositions = false) {
  // Set font size relative to viewport
  const textSizeVal = Math.min(windowWidth, windowHeight) / 10;
  textFont(Font, textSizeVal);

  // Measure metrics
  ascent = textAscent();
  descent = textDescent();

  // Measure each character width
  charW = [];
  for (let i = 0; i < textString.length; i++) {
    charW[i] = textWidth(textString.charAt(i));
  }

  // Initialize or clamp positions/velocities
  if (!keepPositions || posX.length !== textString.length) {
    posX = [];
    posY = [];
    velX = [];
    velY = [];
    for (let i = 0; i < textString.length; i++) {
      // Random starting position within bounds
      const w = Math.max(1, charW[i]);
      posX[i] = random(0, Math.max(1, width - w));
      posY[i] = random(ascent, Math.max(ascent + 1, height - descent));

      // Random velocity (-3..3), avoid zero
      velX[i] = random([-3, -2, -1, 1, 2, 3]);
      velY[i] = random([-3, -2, -1, 1, 2, 3]);
    }
  } else {
    // Clamp positions to current bounds after resize
    for (let i = 0; i < textString.length; i++) {
      const w = Math.max(1, charW[i]);
      posX[i] = constrain(posX[i], 0, Math.max(0, width - w));
      posY[i] = constrain(posY[i], ascent, Math.max(ascent, height - descent));
      if (velX[i] === 0) velX[i] = 1;
      if (velY[i] === 0) velY[i] = 1;
    }
  }
}

function draw() {
  clear();
  fill(255);

  for (let i = 0; i < textString.length; i++) {
    // Move
    posX[i] += velX[i];
    posY[i] += velY[i];

    // Bounce horizontally
    if (posX[i] <= 0) {
      posX[i] = 0;
      velX[i] *= -1;
    } else if (posX[i] + charW[i] >= width) {
      posX[i] = Math.max(0, width - charW[i]);
      velX[i] *= -1;
    }

    // Bounce vertically (baseline-aware)
    if (posY[i] - ascent <= 0) {
      posY[i] = ascent;
      velY[i] *= -1;
    } else if (posY[i] + descent >= height) {
      posY[i] = Math.max(ascent, height - descent);
      velY[i] *= -1;
    }

    // Draw character
    text(textString.charAt(i), posX[i], posY[i]);
  }
}