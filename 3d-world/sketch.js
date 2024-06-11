let len;
let surface;
let sphereRadius;
let xoff = 0.0; // new noise offset variable
let nX, nY; // global variables for noise-adjusted mouseX, mouseY

function preload() {
  surface = loadImage("surface.png");
}

function setup() {
  createCanvas(windowWidth, windowHeight, WEBGL);
  len = 2 * sqrt(sq(windowWidth) + sq(windowHeight));
  sphereRadius = min(windowWidth, windowHeight) / 10;
  noiseDetail(4, 0.5);
}

function draw() {
  background(0);

  // introducing noise to mouse x,y positions
  nX = noise(xoff) * width;
  nY = noise(xoff + 1000) * height;

  push();
  translate(0, 0, -len/2);
  texture(surface);
  plane(len, len);
  pop();

  let camX = map(nX, 0, width, -PI, PI);
  let camY = map(nY, 0, height, -PI/2, PI/2);

  let spherePoints = [];

  for (let i = 0; i < 2; i++) {
    for (let j = 0; j < 2; j++) {
      let angleOffset = ((i + j) % 2 === 0) ? 0 : PI;
      let sphereX = (width / 4 * i) + cos(angleOffset) * 200;
      let sphereY = (height / 4 * j) + sin(angleOffset) * 200;
      spherePoints.push({x: sphereX, y: sphereY});

      let r = nY / width;
      let g = 200 + nX / height;
      let b = nX / height;

      push();
      translate(sphereX, sphereY);
      rotateX(camY);
      rotateY(camX);
      ambientMaterial(r*g, g, b*r);
      strokeWeight(2);
      stroke(spheresAreTouching(spherePoints, sphereRadius) ? 255 : 0);
      createNoiseSphere(sphereRadius);
      pop();
    }
  }

  push();
  translate(0, 0, 10);
  let overlayColor = map(noise(nX / 100, nY / 100), 0, 1, 0, 100);
  fill(0, overlayColor, 0, 100);
  rectMode(CENTER);
  rect(0, 0, width, height);
  pop();

  // increment xoff
  xoff += 0.01;
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  len = 2 * sqrt(sq(windowWidth) + sq(windowHeight));
  sphereRadius = min(windowWidth, windowHeight) / 10;
}

function createNoiseSphere(radius) {
  noiseSeed(nX / 2 * nY / 2); // now it works

  let total = 100;
  let increment = TWO_PI / total;

  for (let lat = 0; lat < PI; lat += increment) {
    beginShape(TRIANGLE_STRIP);
    for (let lon = 0; lon <= TWO_PI; lon += increment) {
      let zoom = map(dist(nX, nY, width / 2, height / 2), 0, dist(0, 0, width / 2, height / 2), 4, 0.25);
      let r = radius * (1 + zoom * noise(lon, lat));

      let offsetX = map(noise(lon, lat, frameCount / 60), 0, 1, -120, 120);
      let offsetY = map(noise(lat, lon, frameCount / 60), 0, 1, -120, 120);
      let offsetZ = map(noise(lat, lon, frameCount / 60), 0, 1, -120, 120);

      vertex((r + offsetX) * sin(lat) * cos(lon),
             (r + offsetY) * sin(lat) * sin(lon),
             (r + offsetZ) * cos(lat));

      r = radius * (1 + zoom * noise(lon, lat + increment));

      vertex((r + offsetX) * sin(lat + increment) * cos(lon),
             (r + offsetY) * sin(lat + increment) * sin(lon),
             (r + offsetZ) * cos(lat + increment));
    }
    endShape();
  }
}

function spheresAreTouching(spherePoints, sphereRadius) {
  for (let i = 0; i < spherePoints.length; i++) {
    for (let j = i + 1; j < spherePoints.length; j++) {
      if (dist(spherePoints[i].x, spherePoints[i].y, spherePoints[j].x, spherePoints[j].y) <= 2 * sphereRadius) {
        return true;
      }
    }
  }
  return false;
}