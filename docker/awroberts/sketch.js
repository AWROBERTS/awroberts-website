let vid;

function setup() {
  createCanvas(windowWidth, windowHeight, WEBGL);

  vid = createVideo('/awroberts-media/background.mp4');
  vid.elt.setAttribute('crossorigin', 'anonymous');
  vid.volume(0);
  vid.attribute('muted', '');
  vid.attribute('playsinline', '');
  vid.attribute('autoplay', '');
  vid.loop();
  vid.play();
  vid.show(); // keep visible for debugging
}

function draw() {
  background(0);

  // Ensure the video is fully ready
  if (vid.elt.readyState === 4) {
    vid.loadPixels(); // force texture update
    resetMatrix();
    noStroke();
    texture(vid);
    plane(width, height);
  }
}

function mousePressed() {
  vid.play();
}
