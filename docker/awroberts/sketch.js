let vid;

function setup() {
  createCanvas(windowWidth, windowHeight, WEBGL);

  vid = createVideo('/awroberts-media/background.mp4', () => {
    vid.volume(0);
    vid.attribute('muted', '');
    vid.attribute('playsinline', '');
    vid.attribute('autoplay', '');
    vid.elt.crossOrigin = "anonymous";
    vid.loop();
    vid.play();
  });

  vid.hide();
}

function draw() {
  background(0);

  if (bgVideo.elt.readyState >= 2) {
    resetMatrix();            // ensures camera is neutral
    noStroke();
    texture(bgVideo);
    plane(width, height);     // full-screen quad
  }
}

function mousePressed() {
  vid.play();
}
