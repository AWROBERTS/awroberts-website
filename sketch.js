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
  strokeWeight(10);
  textFont(Font, 100); // update the font size to 100

  let textString = 'info@awroberts.co.uk';
  for(let i = 0; i < textString.length; i++) {
    noiseOffset[i] = random(10000);
    flickerRate[i] = ((second() + 1) / 200); // half of the original flicker rate
  }
}

function draw() {
  clear(); // making background transparent

  let textString = 'info@awroberts.co.uk';
  let xStart = 100;

  for(let i = 0; i < textString.length; i++) {
    // use perlin noise for the flickering effect
    let n = noise(noiseOffset[i]) * 255;

    // draw the character in flickering color
    let r = n;
    let g = 255 - n;
    let b = 0;

    fill(r, g, b, globalVideoAlpha);
    text(textString.charAt(i), xStart, 130);

    // increment xStart for the next character
    xStart += textWidth(textString.charAt(i));

    // increment the noise offset for the next frame at a rate determined by the current second
    noiseOffset[i] += flickerRate[i];
  }
}