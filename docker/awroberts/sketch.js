let bgVideo;
let curwenFont;
let emailText = 'info@awroberts.co.uk';
let emailSize;
let isHoveringEmail = false;

// deployment JSON
let diag;

// social icons
let icons = {};
let socialLinks = [
  { imgKey: 'github', url: 'https://github.com/awroberts' },
  { imgKey: 'linkedin', url: 'https://www.linkedin.com/in/alexander-roberts-53563312b/' },
  { imgKey: 'bandcamp', url: 'https://chewvalleytapes.bandcamp.com/' }
];
let hoveringSocial = -1;

// fade-in animation
let fadeStartTime;

function preload() {
  curwenFont = loadFont('/awroberts-media/CURWENFONT.ttf');
  diag = loadJSON('/deployment.json');

  // SimpleIcons URLs
  icons.github = loadImage('https://cdn.simpleicons.org/github.svg');
  icons.linkedin = loadImage('https://cdn.simpleicons.org/linkedin.svg');
  icons.bandcamp = loadImage('https://cdn.simpleicons.org/bandcamp.svg');
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

  fadeStartTime = millis();
}

function draw() {
  clear();
  image(bgVideo, 0, 0, width, height);

  drawEmail();
  drawSocialIcons();
  drawDeploymentInfo();
}

function drawEmail() {
  let margin = 30;
  let x = width - margin;
  let y = margin;
  let buffer = 20;

  let textW = textWidth(emailText);

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

function drawSocialIcons() {
  const size = emailSize * 0.8;   // responsive scaling
  const margin = 30;
  const spacing = size + 20;      // horizontal spacing
  const xStart = margin;
  const y = margin;

  hoveringSocial = -1;

  // fade-in alpha (0 → 255 over 1 second)
  let fadeProgress = constrain((millis() - fadeStartTime) / 1000, 0, 1);
  let alpha = fadeProgress * 255;

  socialLinks.forEach((item, i) => {
    let x = xStart + i * spacing;
    let icon = icons[item.imgKey];

    if (icon) {
      push();
      tint(255, alpha); // fade-in + white tint
      image(icon, x, y, size, size);
      pop();
    }

    // Hover detection
    if (
      mouseX > x &&
      mouseX < x + size &&
      mouseY > y &&
      mouseY < y + size
    ) {
      hoveringSocial = i;
      cursor(HAND);

      // highlight box
      push();
      noFill();
      stroke(255, 220, 180, alpha);
      strokeWeight(2);
      rect(x - 4, y - 4, size + 8, size + 8, 4);
      pop();
    }
  });
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
    `kubernetes: ${diag.kubernetes?.version ?? 'N/A'}`,
    `helm: ${diag.helm?.version ?? 'N/A'}`,
    `traefik: ${diag.traefik?.version ?? 'N/A'}`,
    `deployment: ${diag.deployment.name}`,
    `pod: ${diag.pod.name}`,
    `pod ip: ${diag.pod.ip}`,
    `service cluster ip: ${diag.service.clusterIP}`,
    `image tag: ${diag.build.imageTag}`,
    `sha: ${diag.build.sha}`
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
    return;
  }

  if (hoveringSocial !== -1) {
    window.open(socialLinks[hoveringSocial].url, '_blank');
  }
}

function touchStarted() {
  if (touches.length > 0) {
    let tx = touches[0].x;
    let ty = touches[0].y;

    let margin = 30;
    let x = width - margin;
    let y = margin;
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

  // Prevent crash if bgVideo isn't ready yet
  if (bgVideo) {
    bgVideo.size(width, height);
  }

  emailSize = constrain(min(windowWidth, windowHeight) * 0.05, 16, 70);
  textSize(emailSize);
}
