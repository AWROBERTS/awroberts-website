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
  canvas.position(0, 0);
  canvas.style('display', 'block');

  noStroke();
  pixelDensity(Math.min(window.devicePixelRatio || 1, 2));

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
    hls = new Hls({
      enableWorker: true,
      lowLatencyMode: false
    });

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

function drawFullscreenTexture(tex) {
  push();
  resetMatrix();
  ortho();
  translate(-width / 2, -height / 2, 0);
  texture(tex);
  plane(width, height);
  pop();
}

function draw() {
  background(0);

  if (videoEl && videoEl.elt && videoEl.elt.readyState >= 2) {
    drawFullscreenTexture(videoEl);
  } else if (posterImg && posterImg.width > 0) {
    drawFullscreenTexture(posterImg);
  }

  // Rotating cube overlay
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
  resizeCanvas(windowWidth, windowHeight);
  pixelDensity(Math.min(window.devicePixelRatio || 1, 2));
}