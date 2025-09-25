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
  image(bgVideo, 0, 0, width, height); // draw video to canvas
  loadPixels(); // load canvas pixels

  let totalWidth = textWidth(emailText);
  let xStart = width / 2 - totalWidth / 2;
  let y = emailY;

  let x = xStart;
  isHoveringEmail = false;

  for (let i = 0; i < emailText.length; i++) {
    let char = emailText[i];
    let charWidth = textWidth(char);

    let px = int(x + charWidth / 2);
    let py = int(y + emailSize / 2);
    let index = (px + py * width) * 4;

    let r = pixels[index];
    let g = pixels[index + 1];
    let b = pixels[index + 2];

    let ir = 255 - r;
    let ig = 255 - g;
    let ib = 255 - b;

    // Check if mouse is over this character
    let isHoveringChar = mouseX > x && mouseX < x + charWidth && mouseY > y && mouseY < y + emailSize;
    if (isHoveringChar) {
      fill(ir, ig, ib); // inverted pixel color
      isHoveringEmail = true;
    } else {
      fill(255); // pure white
    }

    text(char, x + charWidth / 2, y);
    x += charWidth;
  }

  cursor(isHoveringEmail ? HAND : ARROW);
}

function mousePressed() {
  if (isHoveringEmail) {
    window.location.href = 'mailto:info@awroberts.co.uk';
  }
}