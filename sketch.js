let Font;
let noiseOffset = [];
let flickerRate = [];

function preload() {
    Font = loadFont('CURWENFONT.ttf');
}

function setup() {
    let canvas = createCanvas(windowWidth, windowHeight);
    canvas.parent('canvas-container');
    strokeWeight(20);
    textFont(Font, 80);

    let textString = 'info@awroberts.co.uk';
    for(let i = 0; i < textString.length; i++) {
        noiseOffset[i] = random(10000); // giving each character a random initial offset
        flickerRate[i] = ((second() + 1) / 100) / 2; // giving each character a flicker rate based on the current second
    }
}

function draw() {
    background(255, 0); // ensure the background is transparent

    let textString = 'info@awroberts.co.uk';
    let xStart = 100;

    for(let i = 0; i < textString.length; i++) {
        // Perlin noise gives a value between 0 and 1, multiply by 255 to get full RGB range
        let n = noise(noiseOffset[i]) * 255;

        // For more effect between green and red, we take the value obtained from the Perlin noise n
        // to be the red component, while green component is the inverse of red (255 - n).
        // The blue component is fixed at 0
        let r = n;
        let g = 255 - n;
        let b = 0;

        fill(r, g, b);

        text(textString.charAt(i), xStart, 100);
        xStart += textWidth(textString.charAt(i));

        // increment the noise offset at a rate determined by the current second
        noiseOffset[i] += flickerRate[i];
    }
}