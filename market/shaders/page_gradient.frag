#version 460 core

// The page background: a linear gradient with a little noise added before the
// colour is rounded to 8 bits, so the long, dark, low-contrast gradient does
// not show as visible bands.

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uBegin;
uniform vec2 uEnd;
uniform vec4 uFrom;
uniform vec4 uTo;

out vec4 fragColor;

float hash(vec2 p) {
  vec3 q = fract(vec3(p.xyx) * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 d = uEnd - uBegin;
  float t = clamp(dot(p - uBegin, d) / dot(d, d), 0.0, 1.0);
  vec3 c = mix(uFrom.rgb, uTo.rgb, t);
  // Triangular noise of +-1 step of an 8-bit channel.
  float n = hash(p) + hash(p + 71.7) - 1.0;
  fragColor = vec4(c + n / 255.0, 1.0);
}
