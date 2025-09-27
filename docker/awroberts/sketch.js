let bgVideo;
let curwenFont;
let emailText = 'info@awroberts.co.uk';
let emailSize;
let emailY = 40;
let isHoveringEmail = false;
let rippleRadius = 0;

function preload() {
  curwenFont = loadFont('/awroberts-media/CURWENFONT.ttf');
}

function setup() {
  pixelDensity(1);
  const canvas = createCanvas(windowWidth, windowHeight);
  canvas.parent('canvas-container');
  canvas.style('position', 'absolute');
  canvas.style('top', '0');
  canvas.style('left', '0');
  canvas.style('z-index', '1');

  bgVideo = createVideo('/awroberts-media/background.mp4', () => {
    bgVideo.volume(0);
    bgVideo.attribute('muted', '');
    bgVideo.attribute('playsinline', '');
    bgVideo.attribute('autoplay', '');
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

  emailSize = constrain(windowWidth * 0.1, 24, 140);
  textFont(curwenFont);
  textSize(emailSize);
  textAlign(CENTER, TOP);
}

function draw() {
  // Capture the current video frame
  let frame = bgVideo.get();

  let centerX = (touches.length > 0) ? touches[0].x : mouseX;
  let centerY = (touches.length > 0) ? touches[0].y : mouseY;
  let radius = 75;

  // Create a distorted version of the video frame
  frame.loadPixels();
  loadPixels();
  let d = pixelDensity();

  for (let x = -radius; x <= radius; x++) {
    for (let y = -radius; y <= radius; y++) {
      let dx = centerX + x;
      let dy = centerY + y;
      if (dx >= 0 && dx < width && dy >= 0 && dy < height && x * x + y * y <= radius * radius) {
        let distFactor = sqrt(x * x + y * y);
        let wave = sin(distFactor * 0.3 - frameCount * 0.2) * 5;

        let sx = constrain(dx + wave, 0, width - 1);
        let sy = constrain(dy + wave, 0, height - 1);

        for (let i = 0; i < d; i++) {
          for (let j = 0; j < d; j++) {
            let srcIndex = 4 * ((sy * d + j) * width * d + (sx * d + i));
            let dstIndex = 4 * ((dy * d + j) * width * d + (dx * d + i));

            pixels[dstIndex] = frame.pixels[srcIndex];
            pixels[dstIndex + 1] = frame.pixels[srcIndex + 1];
            pixels[dstIndex + 2] = frame.pixels[srcIndex + 2];
            pixels[dstIndex + 3] = frame.pixels[srcIndex + 3];
          }
        }
      }
    }
  }

  updatePixels();

  // Draw email text on top
  let totalWidth = textWidth(emailText);
  let xStart = width / 2 - totalWidth / 2;
  let yStart = emailY;
  let textHeight = emailSize;

  isHoveringEmail = mouseX > xStart && mouseX < xStart + totalWidth &&
                    mouseY > yStart && mouseY < yStart + textHeight;

  fill(255);
  text(emailText, width / 2, emailY);
  cursor(isHoveringEmail ? HAND : ARROW);
}

function mousePressed() {
  if (isHoveringEmail) {
    window.location.href = 'mailto:info@awroberts.co.uk';
  }
}

function touchStarted() {
  let totalWidth = textWidth(emailText);
  let xStart = width / 2 - totalWidth / 2;
  let yStart = emailY;
  let textHeight = emailSize;

  if (touchX > xStart && touchX < xStart + totalWidth &&
      touchY > yStart && touchY < yStart + textHeight) {
    window.location.href = 'mailto:info@awroberts.co.uk';
  }
  return false;
}

function touchMoved() {
  return false;
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  bgVideo.size(windowWidth, windowHeight);
  emailSize = constrain(windowWidth * 0.1, 24, 140);
  textSize(emailSize);
}
