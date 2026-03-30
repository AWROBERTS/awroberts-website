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

  if (vid.elt.readyState >= 2) {
    texture(vid);
    noStroke();
    plane(width, height);
  }
}

function mousePressed() {
  vid.play();
}
