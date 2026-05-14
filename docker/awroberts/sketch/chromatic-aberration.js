// chromatic-aberration.js — pulsing RGB channel shift

let feOffsetR = null;
let feOffsetB = null;
let caT       = 0;

const CA_SPEED      = 0.012; // speed of the pulse cycle
const CA_MAX_OFFSET = 5;     // max px offset for R and B channels

// -----------------------------
// INIT
// -----------------------------
export function initChromaticAberration() {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('style', 'position:absolute;width:0;height:0;overflow:hidden');
  svg.innerHTML = `
    <defs>
      <filter id="chromab" x="-5%" y="0%" width="110%" height="100%" color-interpolation-filters="sRGB">
        <feColorMatrix type="matrix" values="1 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 1 0" in="SourceGraphic" result="r"/>
        <feColorMatrix type="matrix" values="0 0 0 0 0  0 1 0 0 0  0 0 0 0 0  0 0 0 1 0" in="SourceGraphic" result="g"/>
        <feColorMatrix type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 1 0 0  0 0 0 1 0" in="SourceGraphic" result="b"/>
        <feOffset id="ca-r" dx="0" dy="0" in="r" result="roff"/>
        <feOffset id="ca-b" dx="0" dy="0" in="b" result="boff"/>
        <feComposite in="roff" in2="g" operator="arithmetic" k1="0" k2="1" k3="1" k4="0" result="rg"/>
        <feComposite in="rg" in2="boff" operator="arithmetic" k1="0" k2="1" k3="1" k4="0"/>
      </filter>
    </defs>
  `;
  document.body.appendChild(svg);
  feOffsetR = document.getElementById('ca-r');
  feOffsetB = document.getElementById('ca-b');
}

// -----------------------------
// UPDATE
// -----------------------------
export function updateChromaticAberration() {
  if (!feOffsetR || !feOffsetB) return;
  caT += CA_SPEED;
  // Two overlapping sines for an organic, non-repeating pulse
  const intensity = (0.5 + 0.5 * Math.sin(caT)) * (0.5 + 0.5 * Math.sin(caT * 0.37));
  const offset    = CA_MAX_OFFSET * intensity;
  feOffsetR.setAttribute('dx', String(-offset));
  feOffsetB.setAttribute('dx', String(offset));
}
