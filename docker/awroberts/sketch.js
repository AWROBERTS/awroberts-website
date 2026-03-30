let bgVideo;
let curwenFont;
let emailText = 'info@awroberts.co.uk';
let emailSize;
let emailY = 40;
let isHoveringEmail = false;

let diag;

function preload() {
  curwenFont = loadFont('/awroberts-media/CURWENFONT.ttf');
  diag = loadJSON('/deployment.json');
}

function setup() {
  pixelDensity(1);
  createCanvas(windowWidth, windowHeight, WEBGL);

  bgVideo = createVideo('/awroberts-media/background.mp4');
  bgVideo.elt.setAttribute('crossorigin', 'anonymous');
  bgVideo.volume(0);
  bgVideo.attribute('muted', '');
  bgVideo.attribute('playsinline', '');
  bgVideo.attribute('autoplay', '');
  bgVideo.loop();
  bgVideo.play();

  // Keep video in DOM and composited
  bgVideo.style('position', 'absolute');
  bgVideo.style('top', '0');
  bgVideo.style('left', '0');
  bgVideo.style('width', '1px');
  bgVideo.style('height', '1px');
  bgVideo.style('opacity', '0');
  bgVideo.style('pointer-events', 'none');

  emailSize = constrain(min(windowWidth, windowHeight) * 0.1, 24, 140);
  textFont(curwenFont);
  textAlign(CENTER, TOP);
}

function draw() {
  clear();

  if (bgVideo && bgVideo.elt.readyState === 4) {
    push();
    resetMatrix();
    noStroke();
    texture(bgVideo);
    plane(width, height);
    pop();
  }

  drawEmail();
  drawDeploymentInfo();
}

function drawEmail() {
  let totalWidth = textWidth(emailText);

  let mx = mouseX - width / 2;
  let my = mouseY - height / 2;

  let xStart = -totalWidth / 2;
  let yStart = -height / 2 + emailY;
  let buffer = 20;

  isHoveringEmail =
    mx > xStart - buffer &&
    mx < xStart + totalWidth + buffer &&
    my > yStart - buffer &&
    my < yStart + emailSize + buffer;

  if (isHoveringEmail) {
    fill(255, 220, 180);
    textSize(emailSize * 1.05);
    cursor(HAND);
  } else {
    fill(255);
    textSize(emailSize);
    cursor(ARROW);
  }

  text(emailText, 0, -height / 2 + emailY);
}

function drawDeploymentInfo() {
  if (!diag) return;

  const baseSize = min(windowWidth, windowHeight) * 0.02;
  textSize(baseSize);
  textAlign(LEFT);
  fill(255);

  const margin = 30;
  let x = -width / 2 + margin;
  let y = height / 2 - margin;

  const lines = [
    `Deployment: ${diag.deployment.name}`,
    `Pod: ${diag.pod.name}`,
    `Pod IP: ${diag.pod.ip}`,
    `Service ClusterIP: ${diag.service.clusterIP}`,
    `Image Tag: ${diag.build.imageTag}`,
    `SHA: ${diag.build.sha}`
  ];

  for (let i = lines.length - 1; i >= 0; i--) {
    text(lines[i], x, y);
    y -= baseSize * 1.3;
  }
}

function mousePressed() {
  if (isHoveringEmail) {
    window.location.href = 'mailto:info@awroberts.co.uk';
  }
}

function touchStarted() {
  if (touches.length > 0) {
    let tx = touches[0].x - width / 2;
    let ty = touches[0].y - height / 2;

    let totalWidth = textWidth(emailText);
    let xStart = -totalWidth / 2;
    let yStart = -height / 2 + emailY;

    if (
      tx > xStart &&
      tx < xStart + totalWidth &&
      ty > yStart &&
      ty < yStart + emailSize
    ) {
      window.location.href = 'mailto:info@awroberts.co.uk';
    }
  }
  return false;
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  emailSize = constrain(min(windowWidth, windowHeight) * 0.1, 24, 140);
}
