let soundStarted = false;
let osc;
let reverb;
let gainNode;

function setup() {
  const canvas = createCanvas(windowWidth, windowHeight);
  canvas.parent('canvas-container');
  noStroke();

  osc = new p5.Oscillator('sine');
  osc.freq(110);
  osc.amp(0);

  reverb = new p5.Reverb();
  gainNode = new p5.Gain();

  osc.disconnect();
  osc.connect(gainNode);
  gainNode.connect(reverb);

  reverb.process(gainNode, 3, 2);

  const btn = document.getElementById('start-button');
  btn.addEventListener('click', startSound);
}

function draw() {
  background(0);

  fill(255);
  textAlign(CENTER, CENTER);
  textSize(24);
  text(soundStarted ? 'Sound is running' : 'Click to start sound', width / 2, height / 2);

  const t = millis() * 0.001;
  fill(127, 203, 255);
  circle(width / 2 + sin(t) * 80, height / 2 + cos(t * 1.3) * 50, 40);
}

function startSound() {
  if (soundStarted) return;
  soundStarted = true;

  const overlay = document.getElementById('start-overlay');
  if (overlay) overlay.style.display = 'none';

  userStartAudio();
  getAudioContext().resume().then(() => {
    osc.start();
    osc.amp(0.08, 1.0);

    setInterval(() => {
      if (!soundStarted) return;
      const nextFreq = random([110, 130.81, 146.83, 164.81, 196, 220]);
      osc.freq(nextFreq, 0.2);
    }, 2000);
  });
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
}