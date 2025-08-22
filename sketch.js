let Font;
const textString = 'info@awroberts.co.uk';

let posX = 0;   // left of the text
let posY = 0;   // baseline of the text
let velX = 0;
let velY = 0;

let ascent = 0;
let descent = 0;
let textW = 0;

function preload() {
  Font = loadFont('/awroberts-media/CURWENFONT.ttf');
}

function setup() {
  const canvas = createCanvas(windowWidth, windowHeight);
  canvas.parent('canvas-container');
  pixelDensity(1);
  noStroke();
  textAlign(LEFT, BASELINE);
  initLayout(false);
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  initLayout(true);
}

function initLayout(keepPosition = false) {
  // Set font size relative to viewport
  const textSizeVal = Math.min(windowWidth, windowHeight) / 10;
  textFont(Font, textSizeVal);

  // Metrics and total width
  ascent = textAscent();
  descent = textDescent();
  textW = textWidth(textString);

  // Bounds for top half: baseline must stay in [ascent, height/2 - descent]
  const minX = 0;
  const maxX = Math.max(0, width - textW);
  const minY = ascent;
  const maxY = Math.max(ascent, height / 2 - descent);

  if (!keepPosition) {
    // Start at a random valid position in the top half
    posX = random(minX, maxX);
    posY = random(minY, maxY);

    // Give it a non-zero velocity
    const choices = [-3, -2, -1, 1, 2, 3];
    velX = random(choices);
    velY = random(choices);
  } else {
    // Clamp to new bounds after resize
    posX = constrain(posX, minX, maxX);
    posY = constrain(posY, minY, maxY);
    if (velX === 0) velX = 1;
    if (velY === 0) velY = 1;
  }
}

function draw() {
  clear();
  fill(255);

  // Bounds for current frame
  const minX = 0;
  const maxX = Math.max(0, width - textW);
  const minY = ascent;
  const maxY = Math.max(ascent, height / 2 - descent);

  // Move
  posX += velX;
  posY += velY;

  // Bounce horizontally (keep full string on screen)
  if (posX <= minX) {
    posX = minX;
    velX *= -1;
  } else if (posX >= maxX) {
    posX = maxX;
    velX *= -1;
  }

  // Bounce vertically within top half (baseline-aware)
  if (posY <= minY) {
    posY = minY;
    velY *= -1;
  } else if (posY >= maxY) {
    posY = maxY;
    velY *= -1;
  }

  // Draw the full, readable string
  text(textString, posX, posY);
}