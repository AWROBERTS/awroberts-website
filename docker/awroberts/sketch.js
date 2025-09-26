let bgVideo;
let curwenFont;
let emailText = 'info@awroberts.co.uk';
let emailSize;
let emailY = 40;
let isHoveringEmail = false;

function preload() {
  curwenFont = loadFont('/awroberts-media/CURWENFONT.ttf');
}

function setup() {
  pixelDensity(1); // improves performance on high-DPI screens
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

  emailSize = constrain(windowWidth * 0.1, 24, 140); // responsive font size
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

  // Invert pixels in a 50-pixel circle around mouse or touch
  let centerX = mouseIsPressed ? mouseX : (touches.length > 0 ? touches[0].x : -1);
  let centerY = mouseIsPressed ? mouseY : (touches.length > 0 ? touches[0].y : -1);

  if ((mouseIsPressed || touches.length > 0) && centerX >= 0 && centerY >= 0) {
    loadPixels();
    let d = pixelDensity();
    let radius = 50;

    for (let x = -radius; x <= radius; x++) {
      for (let y = -radius; y <= radius; y++) {
        let dx = centerX + x;
        let dy = centerY + y;
        if (dx >= 0 && dx < width && dy >= 0 && dy < height && x * x + y * y <= radius * radius) {
          for (let i = 0; i < d; i++) {
            for (let j = 0; j < d; j++) {
              let index = 4 * ((dy * d + j) * width * d + (dx * d + i));
              pixels[index] = 255 - pixels[index];         // Red
              pixels[index + 1] = 255 - pixels[index + 1]; // Green
              pixels[index + 2] = 255 - pixels[index + 2]; // Blue
              // Alpha remains unchanged
            }
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
  return false; // prevent default scrolling
}

function touchMoved() {
  return false; // prevent default scrolling during touch drag
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  bgVideo.size(windowWidth, windowHeight);
  emailSize = constrain(windowWidth * 0.1, 24, 140);
  textSize(emailSize);
}
