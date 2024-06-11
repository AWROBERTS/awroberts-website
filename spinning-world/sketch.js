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
  sphereRadius = min(windowWidth, windowHeight) / 2;
  noiseDetail(12, 0.5);
}

function draw() {
  background(0);
  nX = noise(xoff + mouseX) * width;
  nY = noise(xoff + 1000 + mouseY) * height;

  push();
  translate(0, 0, -len/2);
  texture(surface);
  plane(len, len);
  pop();

  push();
  let camAngle = millis() / 5000.0;
  rotateZ(camAngle);

  let sphereX = 0;
  let sphereY = 0;

  push();
  translate(sphereX, sphereY);
  rotateZ(camAngle);
  ambientMaterial(0, (millis() / 10) % 255, 0);
  strokeWeight(2);
  stroke(0);
  createNoiseSphere(sphereRadius);
  pop();

  xoff += 0.06; // Adjusted to make rate of change 4 times slower.
  pop();
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  len = 2 * sqrt(sq(windowWidth) + sq(windowHeight));
  sphereRadius = min(windowWidth, windowHeight) / 2;
}

function createNoiseSphere(radius) {
  noiseSeed(nX / 2 * nY / 2);

  let total = map(mouseX + mouseY, 0, windowWidth + windowHeight, 20, 200);
  let increment = TWO_PI / total;

  for (let lat = 0; lat < PI; lat += increment) {
    beginShape(TRIANGLE_STRIP);
    for (let lon = 0; lon <= TWO_PI; lon += increment) {
      let zoom = map(dist(nX, nY, width / 2, height / 2),
        0, dist(0, 0, width / 2, height / 2),
        4, 0.25);
      let rad = radius * (1 + zoom * noise(lon, lat));

      let offsetX = map(noise(lon, lat, frameCount / 240), 0, 1, -360, 360);
      let offsetY = map(noise(lat, lon, frameCount / 240), 0, 1, -360, 360);
      let offsetZ = map(noise(lat, lon, frameCount / 240), 0, 1, -360, 360);

      stroke(0, (millis() / 10) % 255, 0);

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