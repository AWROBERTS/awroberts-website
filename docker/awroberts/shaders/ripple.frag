precision mediump float;

uniform sampler2D tex;
uniform vec2 resolution;
uniform vec2 mouse;
uniform float time;

varying vec2 vTexCoord;

void main() {
  vec2 uv = vTexCoord;
  vec2 center = mouse / resolution;

  float dist = distance(uv, center);
  float ripple = sin(dist * 40.0 - time * 5.0) * 0.005;

  vec2 rippleUV = uv + normalize(uv - center) * ripple;

  gl_FragColor = texture2D(tex, rippleUV);
}
