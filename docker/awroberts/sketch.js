let bgVideo;
let curwenFont;
let emailText = 'info@awroberts.co.uk';
let emailSize = 140;
let emailY = 40;
let textBuffer;
let isHoveringEmail = false;

function preload() {
  curwenFont = loadFont('/awroberts-media/CURWENFONT.ttf');
}

function setup() {
  const canvas = createCanvas(windowWidth, windowHeight);
  canvas.parent('canvas-container');
  canvas.style('position', 'absolute');
  canvas.style('top', '0');
  canvas.style('left', '0');
  canvas.style('z-index', '1');

  bgVideo = createVideo('/awroberts-media/background.mp4', () => {
    bgVideo.volume(0);
    bgVideo.attribute('muted', '');
    bgVideo.loop();
    bgVideo.play();
  });

  bgVideo.parent('canvas-container');
  bgVideo.size(windowWidth, windowHeight);
  bgVideo.style('position', 'absolute');
  bgVideo.style('top', '0');
  bgVideo.style('left', '0');
  bgVideo.style('z-index', '0');
  bgVideo.style('object-fit', 'cover');

  textFont(curwenFont);
  textSize(emailSize);
  textAlign(CENTER, TOP);

  // Create buffer for text rendering
  textBuffer = createGraphics(width, height);
  textBuffer.textFont(curwenFont);
  textBuffer.textSize(emailSize);
  textBuffer.textAlign(CENTER, TOP);
  textBuffer.clear();
}

function draw() {
  image(bgVideo, 0, 0, width, height);

  let totalWidth = textWidth(emailText);
  let xStart = width / 2 - totalWidth / 2;
  let yStart = emailY;
  let textHeight = emailSize;

  // Check hover
  isHoveringEmail = mouseX > xStart && mouseX < xStart + totalWidth &&
                    mouseY > yStart && mouseY < yStart + textHeight;

  // Clear and draw white text to buffer
  textBuffer.clear();
  textBuffer.fill(255);
  textBuffer.text(emailText, width / 2, emailY);

  if (isHoveringEmail) {
    textBuffer.loadPixels();
    for (let y = yStart; y < yStart + textHeight; y++) {
      for (let x = xStart; x < xStart + totalWidth; x++) {
        let index = (int(x) + int(y) * width) * 4;
        let r = textBuffer.pixels[index];
        let g = textBuffer.pixels[index + 1];
        let b = textBuffer.pixels[index + 2];
        let a = textBuffer.pixels[index + 3];

        // Invert only visible text pixels
        if (a > 0) {
          textBuffer.pixels[index]     = 255 - r;
          textBuffer.pixels[index + 1] = 255 - g;
          textBuffer.pixels[index + 2] = 255 - b;
        }
      }
    }
    textBuffer.updatePixels();
    cursor(HAND);
  } else {
    cursor(ARROW);
  }

  // Draw buffer to main canvas
  image(textBuffer, 0, 0);
}

function mousePressed() {
  if (isHoveringEmail) {
    window.location.href = 'mailto:info@awroberts.co.uk';
  }
}
