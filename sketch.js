let Font;
function preload() {
  Font = loadFont('CURWENFONT.ttf');
}

function setup() {
  createCanvas(600, 200);
  fill('rgb(0,255,0)');
  strokeWeight(10);
  textFont(Font, 40);
  text('info@awroberts.co.uk', 100, 100);
}

function draw() {}