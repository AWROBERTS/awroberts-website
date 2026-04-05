let posterImg;
let videoEl;
let hls;

const VIDEO_URL = "https://awroberts.co.uk/stream/index.m3u8?v=" + Date.now();
const CANVAS_WIDTH = 3840;
const CANVAS_HEIGHT = 2160;

function preload() {
  posterImg = loadImage('/awroberts-media/background-poster.png');
}

function setup() {
  const canvas = createCanvas(CANVAS_WIDTH, CANVAS_HEIGHT, WEBGL);
  canvas.parent('canvas-container');
  noStroke();
  pixelDensity(1);

  videoEl = createVideo('');
  videoEl.hide();
  videoEl.volume(0);

  videoEl.elt.muted = true;
  videoEl.elt.playsInline = true;
  videoEl.elt.autoplay = true;
  videoEl.elt.crossOrigin = 'anonymous';

  if (videoEl.elt.canPlayType('application/vnd.apple.mpegurl')) {
    videoEl.elt.src = VIDEO_URL;
    videoEl.elt.load();
    videoEl.elt.play().catch(err => console.warn('native HLS play failed:', err));
  } else if (window.Hls && Hls.isSupported()) {
    hls = new Hls();
    hls.loadSource(VIDEO_URL);
    hls.attachMedia(videoEl.elt);

    hls.on(Hls.Events.MANIFEST_PARSED, () => {
      videoEl.elt.play().catch(err => console.warn('HLS play failed:', err));
    });

    hls.on(Hls.Events.ERROR, (event, data) => {
      console.warn('HLS error:', data);
    });
  } else {
    console.error('HLS is not supported in this browser.');
  }
}

function draw() {
  background(0);

  // Draw the background video full-frame at 4K
  if (videoEl && videoEl.elt && videoEl.elt.readyState >= 2) {
    push();
    translate(0, 0, -500);
    texture(videoEl);
    plane(width, height);
    pop();
  } else if (posterImg && posterImg.width > 0) {
    push();
    translate(0, 0, -500);
    texture(posterImg);
    plane(width, height);
    pop();
  }

  // Simple proof that WEBGL is working
  push();
  rotateY(frameCount * 0.01);
  rotateX(frameCount * 0.008);
  ambientLight(180);
  directionalLight(255, 255, 255, 0.5, 0.5, -1);
  normalMaterial();
  box(min(width, height) * 0.25);
  pop();
}

function windowResized() {
  // Keep the canvas locked to 4K
  resizeCanvas(CANVAS_WIDTH, CANVAS_HEIGHT);
}