let bgVideo;
let curwenFont;
let emailText = 'info@awroberts.co.uk';
let emailSize = 140;
let emailY = 40;
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

  // Draw text in white
  fill(255);
  text(emailText, width / 2, emailY);

  // If hovering, invert pixels in text block
  if (isHoveringEmail) {
    loadPixels();
    for (let y = yStart; y < yStart + textHeight; y++) {
      for (let x = xStart; x < xStart + totalWidth; x++) {
        let index = (int(x) + int(y) * width) * 4;
        pixels[index]     = 255 - pixels[index];     // R
        pixels[index + 1] = 255 - pixels[index + 1]; // G
        pixels[index + 2] = 255 - pixels[index + 2]; // B
        // Alpha remains unchanged
      }
    }
    updatePixels();
    cursor(HAND);
  } else {
    cursor(ARROW);
  }
}

function mousePressed() {
  if (isHoveringEmail) {
    window.location.href = 'mailto:info@awroberts.co.uk';
  }
}
