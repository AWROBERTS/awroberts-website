let bgVideo;
let curwenFont;
let emailText = 'info@awroberts.co.uk';
let emailSize;
let emailY = 40;
let isHoveringEmail = false;

let diag = null;
let rippleBuffer;

function preload() {
  curwenFont = loadFont('/awroberts-media/CURWENFONT.ttf');
}

function setup() {
  createCanvas(windowWidth, windowHeight); // P2D renderer

  // Load deployment info asynchronously
  loadJSON('/deployment.json', d => diag = d);

  // Load 4K background video
  bgVideo = createVideo('/awroberts-media/background.mp4');
  bgVideo.volume(0);
  bgVideo.attribute('muted', '');
  bgVideo.attribute('playsinline', '');
  bgVideo.loop();
  bgVideo.hide(); // safe in P2D

  // Off‑screen buffer for ripple effect
  rippleBuffer = createGraphics(width, height);

  emailSize = constrain(min(windowWidth, windowHeight) * 0.1, 24, 140);
  textFont(curwenFont);
  textAlign(CENTER, TOP);
}

function draw() {
  background(0);

  // Draw video into buffer
  rippleBuffer.image(bgVideo, 0, 0, width, height);

  // Apply ripple effect
  applyRippleEffect();

  // Draw the processed buffer
  image(rippleBuffer, 0, 0, width, height);

  // Overlays
  drawEmail();
  drawDeploymentInfo();
}

function applyRippleEffect() {
  rippleBuffer.loadPixels();

  let cx = mouseX;
  let cy = mouseY;
  let t = millis() * 0.001;

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {

      let dx = x - cx;
      let dy = y - cy;
      let dist = Math.sqrt(dx * dx + dy * dy);

      // Matches your GLSL ripple frequency & speed
      let ripple = Math.sin(dist * 0.15 - t * 5.0) * 5.0;

      // Normalized direction
      let nx = dx / (dist + 0.0001);
      let ny = dy / (dist + 0.0001);

      // Displaced sample position
      let sx = Math.floor(x + nx * ripple);
      let sy = Math.floor(y + ny * ripple);

      sx = constrain(sx, 0, width - 1);
      sy = constrain(sy, 0, height - 1);

      let srcIndex = (sy * width + sx) * 4;
      let dstIndex = (y * width + x) * 4;

      rippleBuffer.pixels[dstIndex]     = rippleBuffer.pixels[srcIndex];
      rippleBuffer.pixels[dstIndex + 1] = rippleBuffer.pixels[srcIndex + 1];
      rippleBuffer.pixels[dstIndex + 2] = rippleBuffer.pixels[srcIndex + 2];
      // alpha stays unchanged
    }
  }

  rippleBuffer.updatePixels();
}

function drawEmail() {
  let totalWidth = textWidth(emailText);

  let mx = mouseX;
  let my = mouseY;

  let xStart = width / 2 - totalWidth / 2;
  let yStart = emailY;
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

  text(emailText, width / 2, emailY);
}

function drawDeploymentInfo() {
  if (!diag) return;

  const baseSize = min(windowWidth, windowHeight) * 0.02;
  textSize(baseSize);
  textAlign(LEFT);
  fill(255);

  const margin = 30;
  let x = margin;
  let y = height - margin;

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
    let tx = touches[0].x;
    let ty = touches[0].y;

    let totalWidth = textWidth(emailText);
    let xStart = width / 2 - totalWidth / 2;
    let yStart = emailY;

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
  rippleBuffer = createGraphics(width, height);
  emailSize = constrain(min(windowWidth, windowHeight) * 0.1, 24, 140);
}
