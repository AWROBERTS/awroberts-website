let bgVideo;
let curwenFont;

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
}

function draw() {
  background(0, 0); // optional: clear canvas

  textFont(curwenFont);
  textSize(100);
  fill(255);
  textAlign(CENTER, TOP);
  text('info@awroberts.co.uk', width / 2, 40);
}

function mousePressed() {
  let textWidthEstimate = textWidth('info@awroberts.co.uk');
  let textHeight = 48;

  let xStart = width / 2 - textWidthEstimate / 2;
  let xEnd = width / 2 + textWidthEstimate / 2;
  let yStart = 40;
  let yEnd = 40 + textHeight;

  if (mouseX > xStart && mouseX < xEnd && mouseY > yStart && mouseY < yEnd) {
    window.location.href = 'mailto:info@awroberts.co.uk';
  }
}

