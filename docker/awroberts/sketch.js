let bgVideo;
let curwenFont;
let emailText = 'info@awroberts.co.uk';
let emailSize;
let emailY = 40;
let isHoveringEmail = false;

let lastX = -1, lastY = -1;
let radius;

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
  bgVideo.size(width, height);
  bgVideo.style('position', 'absolute');
  bgVideo.style('top', '0');
  bgVideo.style('left', '0');
  bgVideo.style('z-index', '0');

  emailSize = constrain(min(windowWidth, windowHeight) * 0.1, 24, 140);
  textFont(curwenFont);
  textSize(emailSize);
  textAlign(CENTER, TOP);

  radius = min(width, height) * 0.03;
}

function draw() {
  clear();
  image(bgVideo, 0, 0, width, height);

  // add a nearly invisible overlay so inversion has pixels to modify
  fill(0, 0, 0, 1);   // 1 alpha = almost invisible
  noStroke();
  rect(0, 0, width, height);

  radius = min(width, height) * 0.03;

  drawEmail();

  let cx = touches.length ? touches[0].x : mouseX;
  let cy = touches.length ? touches[0].y : mouseY;

  if (dist(cx, cy, lastX, lastY) > 2) {
    applyInvert(cx, cy);
    lastX = cx;
    lastY = cy;
  }
}

function drawEmail() {
  let totalWidth = textWidth(emailText);
  let xStart = width / 2 - totalWidth / 2;
  let yStart = emailY;

  let buffer = 20;

  isHoveringEmail =
    mouseX > xStart - buffer &&
    mouseX < xStart + totalWidth + buffer &&
    mouseY > yStart - buffer &&
    mouseY < yStart + emailSize + buffer;

  if (isHoveringEmail) {
    fill(255, 220, 180);
    textSize(emailSize * 1.05);
    cursor(HAND);
  } else {
    fill(255);
    textSize(emailSize);
    cursor(ARROW);
  }

  text(emailText, width / 2, emailY);
}

function applyInvert(cx, cy) {
  loadPixels();
  let d = pixelDensity();

  for (let x = -radius; x <= radius; x++) {
    for (let y = -radius; y <= radius; y++) {
      if (x * x + y * y > radius * radius) continue;

      let dx = cx + x;
      let dy = cy + y;

      if (dx < 0 || dx >= width || dy < 0 || dy >= height) continue;

      for (let i = 0; i < d; i++) {
        for (let j = 0; j < d; j++) {
          let index = 4 * ((dy * d + j) * width * d + (dx * d + i));
          pixels[index] = 255 - pixels[index];
          pixels[index + 1] = 255 - pixels[index + 1];
          pixels[index + 2] = 255 - pixels[index + 2];
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
  if (touches.length > 0) {
    let tx = touches[0].x;
    let ty = touches[0].y;

    let totalWidth = textWidth(emailText);
    let xStart = width / 2 - totalWidth / 2;
    let yStart = emailY;

    if (tx > xStart && tx < xStart + totalWidth &&
        ty > yStart && ty < yStart + emailSize) {
      window.location.href = 'mailto:info@awroberts.co.uk';
    }
  }
  return false;
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);

  bgVideo.size(width, height);

  emailSize = constrain(min(windowWidth, windowHeight) * 0.1, 24, 140);
  textSize(emailSize);

  radius = min(width, height) * 0.03;

  lastX = -1;
  lastY = -1;
}
