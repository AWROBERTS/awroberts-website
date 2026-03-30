let bgVideo;
let curwenFont;
let emailText = 'info@awroberts.co.uk';
let emailSize;
let isHoveringEmail = false;

// deployment JSON
let diag;

function preload() {
  curwenFont = loadFont('/awroberts-media/CURWENFONT.ttf');
  diag = loadJSON('/deployment.json');
}

function setup() {
  pixelDensity(1);

  const canvas = createCanvas(windowWidth, windowHeight);
  canvas.parent('canvas-container');
  canvas.style('position', 'absolute');
  canvas.style('top', '0');
  canvas.style('left', '0');
  canvas.style('z-index', '1');

  bgVideo = createVideo('/awroberts-media/background.mp4', () => {
    bgVideo.volume(0);
    bgVideo.attribute('muted', '');
    bgVideo.attribute('playsinline', '');
    bgVideo.attribute('autoplay', '');
    bgVideo.loop();
    bgVideo.play();
  });

  bgVideo.hide();

  emailSize = constrain(min(windowWidth, windowHeight) * 0.05, 16, 70);

  textFont(curwenFont);
  textSize(emailSize);
  textAlign(RIGHT, TOP);
}

function draw() {
  clear();
  image(bgVideo, 0, 0, width, height);

  drawEmail();
  drawDeploymentInfo();
}

function drawEmail() {
  let margin = 30;
  let x = width - margin;
  let y = margin;
  let buffer = 20;

  let textW = textWidth(emailText);

  // Hover detection (right-aligned)
  isHoveringEmail =
    mouseX > x - textW - buffer &&
    mouseX < x + buffer &&
    mouseY > y - buffer &&
    mouseY < y + emailSize + buffer;

  if (isHoveringEmail) {
    fill(255, 220, 180);
    textSize(emailSize * 1.05);
    cursor(HAND);
  } else {
    fill(255);
    textSize(emailSize);
    cursor(ARROW);
  }

  textAlign(RIGHT, TOP);
  text(emailText, x, y);
}

function drawDeploymentInfo() {
  if (!diag) return;

  const baseSize = min(windowWidth, windowHeight) * 0.02;
  textSize(baseSize);
  textAlign(LEFT);
  fill(255);

  const margin = 30;
  let x = margin;

  const lines = [
    `Kubernetes: ${diag.kubernetes?.version ?? 'N/A'}`,
    `Traefik: ${diag.traefik?.version ?? 'N/A'}`,
    `Deployment: ${diag.deployment.name}`,
    `Pod: ${diag.pod.name}`,
    `Pod IP: ${diag.pod.ip}`,
    `Service ClusterIP: ${diag.service.clusterIP}`,
    `Image Tag: ${diag.build.imageTag}`,
    `SHA: ${diag.build.sha}`
  ];

  let y = height - margin - (baseSize * 1.3 * lines.length);

  for (let i = 0; i < lines.length; i++) {
    text(lines[i], x, y);
    y += baseSize * 1.3;
  }
}

function mousePressed() {
  if (isHoveringEmail) {
    window.location.href = 'mailto:info@awroberts.co.uk';
  }
}

function touchStarted() {
  if (touches.length > 0) {
    let tx = touches[0].x;
    let ty = touches[0].y;

    let x = width - 30;
    let y = 30;
    let textW = textWidth(emailText);

    if (
      tx > x - textW &&
      tx < x &&
      ty > y &&
      ty < y + emailSize
    ) {
      window.location.href = 'mailto:info@awroberts.co.uk';
    }
  }
  return false;
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  bgVideo.size(width, height);

  emailSize = constrain(min(windowWidth, windowHeight) * 0.05, 16, 70);
  textSize(emailSize);
}
