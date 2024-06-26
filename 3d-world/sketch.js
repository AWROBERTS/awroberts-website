let len;
let surface;
let sphereRadius;
let xoff = 0.0;
let nX, nY;
let mx, my;
let mouseIsMoving = false;

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
  // Check if mouse is moving
  if (mouseX !== mx || mouseY !== my) {
    mouseIsMoving = true;
  } else {
    mouseIsMoving = false;
  }
  mx = mouseX;
  my = mouseY;

  background(0);
  nX = noise(xoff) * width;
  nY = noise(xoff + 1000) * height;

  push();
  translate(0, 0, -len/2);
  texture(surface);
  plane(len, len);
  pop();

  if (mouseIsMoving) {
    // Modify this section to change behavior when mouse is moving
    push();
    let camAngle = millis() / 5000.0;
    rotateZ(camAngle);

    var angle = millis() / 1000.0;

    for (let i = 0; i < 2; i++) {
      let sphereX = 200 * cos(angle);
      let sphereY = 200 * sin(angle);

      push();
      translate(sphereX, sphereY);
      rotateZ(camAngle);
      ambientMaterial(i * 255, 0, 0);
      strokeWeight(2);
      stroke(i * 255, 0, 0);
      createNoiseSphere(sphereRadius);
      pop();

      angle += PI;
    }
    pop();
  } else {
    // Modify this section to change behavior when mouse is not moving
    push();
    let camAngle = millis() / 5000.0;
    rotateZ(camAngle);
    let camX = map(nX, 0, width, -PI, PI);
    let camY = map(nY, 0, height, -PI/2, PI/2);

    var angle = millis() / 1000.0;

    for (let i = 0; i < 2; i++) {
      let sphereX = 250 * cos(angle);
      let sphereY = 250 * sin(angle);

      push();
      translate(sphereX, sphereY);
      rotateX(camY);
      rotateY(camX);
      let blackRadius = sphereRadius / 2;
      translate(0, 0, -blackRadius);

      // Draw colored sphere with texture
      texture(surface);
      noStroke();
      sphere(blackRadius);

      // Draw larger dynamic black sphere weighted by noise value
      noFill();
      strokeWeight(map(noise(xoff), 0, 1, 0.2, 2)); // Thinner line based on noise
      stroke(0); // Black color
      sphere(blackRadius);
      pop();

      angle += PI;
    }
    pop();
  }

  xoff += 0.08; // Adjusted for quicker terrain change.
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  len = 2 * sqrt(sq(windowWidth) + sq(windowHeight));
  sphereRadius = min(windowWidth, windowHeight) / 10;
}

function createNoiseSphere(radius) {
  // Only used in second sketch
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

  // Creating inner black spheres
  let blackRadius = radius / 4;
  translate(0, 0, -blackRadius);
  ambientMaterial(0, 0, 0);
  sphere(blackRadius);
}