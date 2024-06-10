let len;
let surface;

function preload() {
  surface = loadImage("surface.png");
}

function setup() {
  createCanvas(windowWidth, windowHeight, WEBGL);
  len = 2 * sqrt(sq(windowWidth) + sq(windowHeight));
  noiseDetail(4, 0.5);
  ambientLight(255);
}

function draw() {
  background(0);

  // Draw image as a background
  push();
  translate(0, 0, -len/2);
  texture(surface);
  plane(len, len);
  pop();

  let camX = map(mouseX, 0, width, -PI, PI);
  let camY = map(mouseY, 0, height, -PI/2, PI/2);

  let lightLevel = map(dist(mouseX, mouseY, width / 2, height / 2), 0, dist(0, 0, width / 2, height / 2), 0, 255);
  ambientLight(lightLevel);

  // Array to hold sphere positions
  let spherePoints = [];

  // Draw 4 spheres
  for (let i = 0; i < 2; i++) {
    for (let j = 0; j < 2; j++) {
      let angleOffset = map(i * j, 0, 3, 0, TWO_PI);
      let sphereX = (width / 8 * 1.25) * cos(angleOffset); // adjusted here
      let sphereY = (height / 8 * 1.25) * sin(angleOffset); // adjusted here
      spherePoints.push({x: sphereX, y: sphereY});

      let whiteStroke = color(255, 255, 255);
      let greenStroke = color(0, 255, 0);

      push();
      stroke(dist(sphereX, sphereY, width / 2, height / 2) <= (200 * 0.8 + 210) ? whiteStroke : greenStroke);
      translate(sphereX, sphereY);
      rotateX(camX);
      rotateY(camY);
      createNoiseSphere(200 * 0.8);
      pop();
    }
  }

  // Checks if the spheres are touching and changes the stroke color accordingly
  let touch = spheresAreTouching(spherePoints);

  // Overlay semi-transparent rectangle
  push();
  translate(0, 0, 10); // on top of everything else
  let overlayColor = map(noise(mouseX / 100, mouseY / 100), 0, 1, 0, 100); // uses Perlin noise
  fill(0, overlayColor, 0, 100); // semi-transparent green
  rectMode(CENTER);
  rect(0, 0, width, height);
  pop();
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  len = 2 * sqrt(sq(windowWidth) + sq(windowHeight));
}

// Checks if any pair of spheres are touching
function spheresAreTouching(spherePoints) {
  // Check every pair of spheres
  for (let i = 0; i < spherePoints.length; i++) {
    for (let j = i + 1; j < spherePoints.length; j++) {
      let distance = dist(spherePoints[i].x, spherePoints[i].y, spherePoints[j].x, spherePoints[j].y);
      // If the distance is less than or equal to the sum of their radii, they are touching
      if (distance <= 210 * 2) {
        return true;
      }
    }
  }
  return false;
}

function createNoiseSphere(radius) {
  noiseSeed(mouseX / 2 * mouseY / 2);
  let total = 100;
  let increment = TWO_PI / total;

  for (let lat = 0; lat < PI; lat += increment) {
      beginShape(TRIANGLE_STRIP);
      for (let lon = 0; lon <= TWO_PI; lon += increment) {
          let zoom = map(dist(mouseX, mouseY, width / 2, height / 2), 0, dist(0, 0, width / 2, height / 2), 2, 0.25);
          let r = radius * (1 + zoom * noise(lon, lat));
          let offsetX = map(noise(lon, lat, frameCount / 60), 0, 1, -120, 120);
          let offsetY = map(noise(lat, lon, frameCount / 60), 0, 1, -120, 120);
          let offsetZ = map(noise(lat, lon, frameCount / 60), 0, 1, -120, 120);
          let x = (r + offsetX) * sin(lat) * cos(lon);
          let y = (r + offsetY) * sin(lat) * sin(lon);
          let z = (r + offsetZ) * cos(lat);
          vertex(x, y, z);
          r = radius * (1 + zoom * noise(lon, lat + increment));
          x = (r + offsetX) * sin(lat + increment) * cos(lon);
          y = (r + offsetY) * sin(lat + increment) * sin(lon);
          z = (r + offsetZ) * cos(lat + increment);
          vertex(x, y, z);
      }
      endShape();
  }
}