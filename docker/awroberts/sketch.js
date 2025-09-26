let bgVideo;
let curwenFont;
let emailText = 'info@awroberts.co.uk';
let emailSize;
let emailY = 40;
let isHoveringEmail = false;
let rippleOrigin = null;

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

  if (rippleOrigin) {
    loadPixels();
    let d = pixelDensity();
    let waveStrength = 10;
    let waveFrequency = 0.05;
    let time = frameCount * 0.1;

    for (let x = 0; x < width; x++) {
      for (let y = 0; y < height; y++) {
        let dx = x - rippleOrigin.x;
        let dy = y - rippleOrigin.y;
        let dist = sqrt(dx * dx + dy * dy);
        let offset = sin(dist * waveFrequency - time) * waveStrength;

        let srcX = constrain(x + offset, 0, width - 1);
        let srcY = constrain(y + offset, 0, height - 1);

        for (let i = 0; i < d; i++) {
          for (let j = 0; j < d; j++) {
            let srcIndex = 4 * ((srcY * d + j) * width * d + (srcX * d + i));
            let dstIndex = 4 * ((y * d + j) * width * d + (x * d + i));

            pixels[dstIndex] = pixels[srcIndex];
            pixels[dstIndex + 1] = pixels[srcIndex + 1];
            pixels[dstIndex + 2] = pixels[srcIndex + 2];
            pixels[dstIndex + 3] = pixels[srcIndex + 3];
          }
        }
      }
    }
    updatePixels();
  }
}

function mousePressed() {
  if (isHoveringEmail) {
    window.location.href = 'mailto:info@awroberts.co.uk';
  } else {
    rippleOrigin = { x: mouseX, y: mouseY };
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
  } else {
    rippleOrigin = { x: touches[0].x, y: touches[0].y };
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
