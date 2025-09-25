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
  let s = second();
  let angle = radians(s * 6); // 6 degrees per second
  let scaleFactor = sqrt(2);  // ~1.414 to cover corners

  push();
  translate(width / 2, height / 2); // Move origin to center
  rotate(angle);                    // Rotate canvas
  imageMode(CENTER);
  image(bgVideo, 0, 0, width * scaleFactor, height * scaleFactor); // Scaled video
  pop();

  // Static email text
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
