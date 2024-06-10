let bg;

function preload(){
  // Load the image
  bg = loadImage('image test.png');
}

function setup() {
  createCanvas(windowWidth, windowHeight, WEBGL);
  // Resize the image to fit the window
  bg.resize(windowWidth/2, windowHeight/2); //resize to half window size
}

function draw() {
  background(0);
  // Rotate the scene according to mouse position
  let camX = map(mouseX, 0, width, -PI, PI);
  let camY = map(mouseY, 0, height, -PI/2, PI/2);

  push();
  translate(-bg.width/2, -bg.height/2, 0); // Translate to move the image at the center
  rotateX(-camY);
  rotateY(-camX);
  image(bg, width/2 - bg.width/2, height/2 - bg.height/2); // Draw the image at the rotated position
  pop();

  // Add ambient light to the scene
  ambientLight(255);

  // Draw still sphere with color dependent on mouse position
  push();
  let green = color(0, 255, 0);
  let purple = color(128, 0, 128);
  let amt = map(dist(mouseX, mouseY, width / 2, height / 2), 0, dist(0, 0, width / 2, height / 2), 0, 1);
  let col = lerpColor(green, purple, amt);
  ambientMaterial(col);
  rotateX(camY);
  rotateY(camX);
  sphere(50);
  pop();
}