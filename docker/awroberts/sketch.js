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
  image(bgVideo, 0, 0, width, height);

  let totalWidth = textWidth(emailText);
  let xStart = width / 2 - totalWidth / 2;
  let yStart = emailY;
  let textHeight = emailSize;

  isHoveringEmail = mouseX > xStart && mouseX < xStart + totalWidth &&
                    mouseY > yStart && mouseY < yStart + textHeight;

  fill(255);
  text(emailText, width / 2, emailY);
  cursor(isHoveringEmail ? HAND : ARROW);

  let centerX = (touches.length > 0) ? touches[0].x : mouseX;
  let centerY = (touches.length > 0) ? touches[0].y : mouseY;

  loadPixels();
  let d = pixelDensity();
  let radius = 75;

  for (let x = -radius; x <= radius; x++) {
    for (let y = -radius; y <= radius; y++) {
      let dx = centerX + x;
      let dy = centerY + y;
      if (dx >= 0 && dx < width && dy >= 0 && dy < height && x * x + y * y <= radius * radius) {
        let wave = sin(sqrt(x * x + y * y) * 0.3 - frameCount * 0.2) * 10;

        for (let i = 0; i < d; i++) {
          for (let j = 0; j < d; j++) {
            let srcX = constrain(dx + wave, 0, width - 1);
            let srcY = constrain(dy + wave, 0, height - 1);
            let srcIndex = 4 * ((srcY * d + j) * width * d + (srcX * d + i));
            let dstIndex = 4 * ((dy * d + j) * width * d + (dx * d + i));

            // Blend distorted pixel with original
            pixels[dstIndex] = (pixels[dstIndex] + pixels[srcIndex]) / 2;
            pixels[dstIndex + 1] = (pixels[dstIndex + 1] + pixels[srcIndex + 1]) / 2;
            pixels[dstIndex + 2] = (pixels[dstIndex + 2] + pixels[srcIndex + 2]) / 2;
          }
        }
      }
    }
  }

  updatePixels();
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
