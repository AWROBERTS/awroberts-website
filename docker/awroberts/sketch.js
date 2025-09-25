let bgVideo;
let curwenFont;
let emailText = 'info@awroberts.co.uk';
let emailSize = 192;
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
  // Calculate text bounds
  let textWidthEstimate = textWidth(emailText);
  let textHeight = emailSize;
  let xStart = width / 2 - textWidthEstimate / 2;
  let xEnd = width / 2 + textWidthEstimate / 2;
  let yStart = emailY;
  let yEnd = emailY + textHeight;

  // Check hover
  isHoveringEmail = mouseX > xStart && mouseX < xEnd && mouseY > yStart && mouseY < yEnd;

  // Set fill color based on hover
  if (isHoveringEmail) {
    fill(255, 255, 200); // yellowish white
    cursor(HAND);
  } else {
    fill(255); // pure white
    cursor(ARROW);
  }

  text(emailText, width / 2, emailY);
}

function mousePressed() {
  if (isHoveringEmail) {
    window.location.href = 'mailto:info@awroberts.co.uk';
  }
}


