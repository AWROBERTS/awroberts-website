let posterImg;
let videoEl;
let hls;

const VIDEO_URL = "https://awroberts.co.uk/stream/index.m3u8?v=" + Date.now();

function preload() {
  posterImg = loadImage('/awroberts-media/background-poster.png');
}

function setup() {
  const canvas = createCanvas(windowWidth, windowHeight, WEBGL);
  canvas.parent('canvas-container');
  noStroke();

  // Create a hidden video element for the HLS stream
  videoEl = createVideo('');
  videoEl.hide();
  videoEl.volume(0);

  videoEl.elt.muted = true;
  videoEl.elt.playsInline = true;
  videoEl.elt.autoplay = true;
  videoEl.elt.crossOrigin = 'anonymous';

  if (videoEl.elt.canPlayType('application/vnd.apple.mpegurl')) {
    // Native HLS support (Safari / iOS)
    videoEl.elt.src = VIDEO_URL;
    videoEl.elt.load();
    videoEl.elt.play().catch(err => console.warn('native HLS play failed:', err));
  } else if (window.Hls && Hls.isSupported()) {
    // hls.js for Chrome / Firefox / Edge
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

  // Simple proof that WEBGL is working
  push();
  rotateY(frameCount * 0.01);
  rotateX(frameCount * 0.008);
  ambientLight(180);
  directionalLight(255, 255, 255, 0.5, 0.5, -1);
  normalMaterial();
  box(min(width, height) * 0.25);
  pop();

  // Draw video once it is ready, otherwise fall back to poster
  if (videoEl && videoEl.elt && videoEl.elt.readyState >= 2) {
    push();
    translate(0, 0, -200);
    texture(videoEl);
    plane(width, height);
    pop();
  } else if (posterImg && posterImg.width > 0) {
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