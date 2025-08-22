let Font;
let noiseOffset = [];
let flickerRate = [];
let globalVideoAlpha = 127;

function preload() {
  Font = loadFont('CURWENFONT.ttf');
}

function setup() {
  let canvas = createCanvas(windowWidth, windowHeight);
  canvas.parent('canvas-container');
  pixelDensity(1);
  canvas.elt.style.mixBlendMode = 'difference'; // invert colors under white draws
  strokeWeight(3); // Set the stroke weight to 3 pixels

  let textString = 'info@awroberts.co.uk';
  for (let i = 0; i < textString.length; i++) {
    noiseOffset[i] = random(10000);
    flickerRate[i] = ((second() + 1) / 200); // half of the original flicker rate
  }
  windowResized(); // call windowResized function after setup
}

// This function gets called each time the window size is changed.
function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  let textSize = min(windowWidth, windowHeight) / 10;
  textFont(Font, textSize);
}

function draw() {
  clear(); // making background transparent

  let textString = 'info@awroberts.co.uk';

  // compute the total width of the text
  let totalTextWidth = 0;
  for (let i = 0; i < textString.length; i++) {
    totalTextWidth += textWidth(textString.charAt(i)) * 2;
  }

  // set the start x position to center the text
  let xStart = (windowWidth - totalTextWidth) / 2;

  for (let i = 0; i < textString.length; i++) {
    // use perlin noise for the flickering effect
    let n = noise(noiseOffset[i]) * 255;

    // create a dripping effect by adding randomness to the y-coordinate
    let yDrip = random(130, 140) + windowHeight / 6;

    // draw the character in white; mix-blend-mode 'difference' will invert colors underneath
    // you can still use 'n' to flicker alpha if desired
    stroke(255);
    fill(255, 255, 255, globalVideoAlpha); // white with your alpha
    text(textString.charAt(i), xStart, yDrip);

    // increment xStart for the next character by 2 * character width
    xStart += textWidth(textString.charAt(i)) * 2;

    // increment the noise offset for the next frame at a rate determined by the current second
    noiseOffset[i] += flickerRate[i];
  }
}