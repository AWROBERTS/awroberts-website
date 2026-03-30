let vid;

function setup() {
  createCanvas(windowWidth, windowHeight, WEBGL);

  // Load the video
  vid = createVideo('/awroberts-media/background.mp4', () => {
    vid.volume(0);
    vid.attribute('muted', '');
    vid.attribute('playsinline', '');
    vid.attribute('autoplay', '');
    vid.elt.crossOrigin = "anonymous";
    vid.loop();
    vid.play();
  });

  // IMPORTANT: show the video so Chrome can expose captureStream()
  vid.show();
}

function draw() {
  background(0);

  // Only draw when the video has enough data
  if (vid.elt.readyState >= 2) {
    resetMatrix();
    noStroke();
    texture(vid);
    plane(width, height);
  }
}

function mousePressed() {
  vid.play();
}
