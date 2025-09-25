let bgVideo;

function setup() {
  const canvas = createCanvas(windowWidth, windowHeight);
  canvas.parent('canvas-container');
  canvas.style('position', 'absolute');
  canvas.style('top', '0');
  canvas.style('left', '0');
  canvas.style('z-index', '1');

  bgVideo = createVideo('background.mp4');
  bgVideo.parent('canvas-container');
  bgVideo.size(windowWidth, windowHeight);
  bgVideo.style('z-index', '0');
  bgVideo.style('object-fit', 'cover');
  bgVideo.style('position', 'absolute');
  bgVideo.style('top', '0');
  bgVideo.style('left', '0');
  bgVideo.loop();
  bgVideo.hide();
}

function draw() {
  fill(255, 255, 255, 50);
  rect(0, 0, width, height);
}
