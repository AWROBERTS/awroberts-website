let bgVideo;

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
}

