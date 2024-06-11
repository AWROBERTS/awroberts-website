let len;
let surface;
let sphereRadius;
let xoff = 0.0;
let nX, nY;

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

  for (let i = 0; i <= 2; i++) {
    for (let j = 0; j <= 2; j++) {
      let angleOffset = ((i + j) % 2 === 0) ? 0 : PI;
      let sphereX = (width / 3 * i) + cos(angleOffset) * 200;
      let sphereY = (height / 3 * j) + sin(angleOffset) * 200;
      spherePoints.push({x: sphereX, y: sphereY});

      let isTouching = spheresAreTouching(spherePoints, sphereRadius);

      // Color variables for stroke and ambientMaterial
      let sr, sg, sb, ar, ag, ab;

      if (isTouching) {
        sr = sg = sb = 255; // White color for stroke if spheres are touching
      } else {
        sr = 0; sg = sb = 255; // Neon green color for stroke if spheres are not touching
      }

      if (j % 2 === 0) {
        ar = map(mouseX, 0, width, 0, 255);
        ag = map(mouseY, 0, height, 0, 255);
        ab = 100;
      } else {
        ar = map(mouseX, 0, width, 255, 0);
        ag = map(mouseY, 0, height, 255, 0);
        ab = 100;
      }

      push();
      translate(sphereX, sphereY);
      rotateX(camY);
      rotateY(camX);
      ambientMaterial(ar, ag, ab);
      strokeWeight(2);
      stroke(sr, sg, sb);
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

  xoff += 0.02;
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  len = 2 * sqrt(sq(windowWidth) + sq(windowHeight));
  sphereRadius = min(windowWidth, windowHeight) / 10;
}

function createNoiseSphere(radius) {
  noiseSeed(nX / 2 * nY / 2);

  let total = 100;
  let increment = TWO_PI / total;

  let r = map(millis() % 256, 0, 256, 0, 255);
  let g = map((millis() + 85) % 256, 0, 256, 0, 255);
  let b = map((millis() + 170) % 256, 0, 256, 0, 255);

  for (let lat = 0; lat < PI; lat += increment) {
    beginShape(TRIANGLE_STRIP);
    for (let lon = 0; lon <= TWO_PI; lon += increment) {
      let zoom = map(dist(nX, nY, width / 2, height / 2),
                     0, dist(0, 0, width / 2, height / 2),
                     4, 0.25);
      let rad = radius * (1 + zoom * noise(lon, lat));

      let offsetX = map(noise(lon, lat, frameCount / 240), 0, 1, -120, 120);
      let offsetY = map(noise(lat, lon, frameCount / 240), 0, 1, -120, 120);
      let offsetZ = map(noise(lat, lon, frameCount / 240), 0, 1, -120, 120);

      stroke(r, g, b);

      vertex((rad + offsetX) * sin(lat) * cos(lon),
             (rad + offsetY) * sin(lat) * sin(lon),
             (rad + offsetZ) * cos(lat));

      rad = radius * (1 + zoom * noise(lon, lat + increment));

      vertex((rad + offsetX) * sin(lat + increment) * cos(lon),
             (rad + offsetY) * sin(lat + increment) * sin(lon),
             (rad + offsetZ) * cos(lat + increment));
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