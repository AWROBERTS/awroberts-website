let rippleShader;
let bgVideo;
let curwenFont;
let emailText = 'info@awroberts.co.uk';
let emailSize = 140;
let emailY = 40;
let isHoveringEmail = false;

function preload() {
  rippleShader = loadShader('shaders/ripple.vert', 'shaders/ripple.frag');
  curwenFont = loadFont('/awroberts-media/CURWENFONT.ttf');
  bgVideo = createVideo('/awroberts-media/background.mp4');
  bgVideo.hide(); // Hide default DOM rendering
}

function setup() {
  createCanvas(windowWidth, windowHeight, WEBGL);
  bgVideo.loop();
  bgVideo.volume(0);
  bgVideo.attribute('muted', '');
  bgVideo.play();

  textFont(curwenFont);
  textSize(emailSize);
  textAlign(CENTER, TOP);
  noStroke();
}

function draw() {
  // Apply ripple shader
  shader(rippleShader);
  rippleShader.setUniform('tex', bgVideo);
  rippleShader.setUniform('resolution', [width, height]);
  rippleShader.setUniform('mouse', [mouseX, height - mouseY]); // Flip Y for WebGL
  rippleShader.setUniform('time', millis() / 1000.0);

  // Draw fullscreen quad with shader
  rect(-width / 2, -height / 2, width, height);

  // Overlay static email text
  resetMatrix(); // Reset WebGL transform to draw in screen space
  setAttributes('alpha', true); // Allow blending
  textFont(curwenFont);
  textSize(emailSize);
  textAlign(CENTER, TOP);
  fill(255);

  let totalWidth = textWidth(emailText);
  let xStart = width / 2 - totalWidth / 2;
  let yStart = emailY;
  let textHeight = emailSize;

  isHoveringEmail = mouseX > xStart && mouseX < xStart + totalWidth &&
                    mouseY > yStart && mouseY < yStart + textHeight;

  text(emailText, width / 2, emailY);
  cursor(isHoveringEmail ? HAND : ARROW);
}

function mousePressed() {
  if (isHoveringEmail) {
    window.location.href = 'mailto:info@awroberts.co.uk';
  }
}
