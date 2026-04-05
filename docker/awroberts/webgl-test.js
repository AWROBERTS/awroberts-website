let posterImg;
let videoEl;
let videoReady = false;

function preload() {
  posterImg = loadImage('/awroberts-media/background-poster.png');
}

function setup() {
  const canvas = createCanvas(windowWidth, windowHeight, WEBGL);
  canvas.parent('canvas-container');
  noStroke();

  videoEl = createVideo(['/awroberts-media/background.mp4'], () => {
    console.log('video element ready');
    videoEl.hide();
    videoEl.volume(0);
    videoEl.loop();
    videoEl.play().catch(err => console.warn('video play failed:', err));
  });

  videoEl.elt.muted = true;
  videoEl.elt.playsInline = true;
  videoEl.elt.autoplay = true;
}

function draw() {
  background(0);

  // Simple proof that WEBGL is working
  push();
  rotateY(frameCount * 0.01);
  rotateX(frameCount * 0.008);
  ambientLight(180);
  directionalLight(255, 255, 255, 0.5, 0.5, -1);
  normalMaterial();
  box(min(width, height) * 0.25);
  pop();

  // Draw poster image as a textured plane
  if (posterImg && posterImg.width > 0) {
    push();
    translate(0, 0, -200);
    texture(posterImg);
    plane(width, height);
    pop();
  }
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
}