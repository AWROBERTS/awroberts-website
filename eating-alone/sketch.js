let sounds = [];
let fft;
let index = 0;
let button;

let soundFiles = ['07_06_23.wav'];

function preload() {
  soundFiles.forEach((soundFile, i) => {
    sounds[i] = loadSound('MIXES/' + soundFile, ();
  });
}

function setup() {
    createCanvas(windowWidth, windowHeight);
    fft = new p5.FFT();

    button = createButton('Play');
    button.position(10, 10);
    button.mousePressed(playSound);
}

function draw() {
  background(0);

  if (sounds[index] && sounds[index].isPlaying()) {
    let spectrum = fft.analyze();
    noStroke();
    for (let i = 0; i < spectrum.length; i++) {
      let x = map(i, 0, spectrum.length, 0, width);
      let h = -height + map(spectrum[i], 0, 255, height, 0);
      fill(255, i / 2, 0);
      rect(x, height, width / spectrum.length, h);
    }
  }
}

function playSound() {
  // If no sound is currently playing, then start the next sound
  if (!sounds.some(sound => sound.isPlaying())) {
    sounds[index].play();
    sounds[index].onended(playNextSound);
  }
}

function playNextSound() {
  // Stop the current sound
  sounds[index].stop();

  // Move to the next sound
  index = (index + 1) % sounds.length;
}

// Handling window resize
function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
}