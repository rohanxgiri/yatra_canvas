#version 460 core
#include <flutter/runtime_effect.glsl>

// The engine supplies input texture dimensions and the first sampler.
uniform vec2 uTextureSize;
uniform vec2 uLogicalSize;
uniform float uRadius;
uniform float uDisplacement;
uniform float uSoftness;
uniform sampler2D uBackdrop;
out vec4 fragColor;

vec4 backdrop(vec2 logicalPoint) {
  vec2 uv = clamp(logicalPoint / uLogicalSize,
                  0.5 / uTextureSize, 1.0 - 0.5 / uTextureSize);
  #ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
  #endif
  return texture(uBackdrop, uv);
}

void main() {
  vec2 p = FlutterFragCoord().xy / uTextureSize * uLogicalSize;
  vec2 halfSize = uLogicalSize * 0.5;
  float radius = min(uRadius, min(halfSize.x, halfSize.y));
  vec2 centered = p - halfSize;
  vec2 q = abs(centered) - (halfSize - radius);
  vec2 outside = max(q, vec2(0.0));
  float distance = length(outside) + min(max(q.x, q.y), 0.0) - radius;
  vec2 normal;
  if (length(outside) > 0.001) {
    normal = normalize(outside) * sign(centered);
  } else {
    normal = q.x > q.y ? vec2(sign(centered.x), 0.0)
                        : vec2(0.0, sign(centered.y));
  }
  float band = min(12.0, min(halfSize.x, halfSize.y) * 0.55);
  float edge = 1.0 - smoothstep(0.0, band, max(0.0, -distance));
  float corner = abs(normal.x * normal.y) * 0.3;
  // Inward sampling gives a shallow convex lens. The clear center magnifies
  // only 0.15%; edge displacement is bounded to 3.8 logical px, never animated.
  vec2 samplePoint = p - centered * 0.0015
      - normal * min(3.8, uDisplacement * (1.0 + corner)) * edge * edge;
  // A small, normalized nine-tap backdrop softening kernel, in logical px.
  // Integrated here to avoid an extra blur pass inflating shader input bounds.
  vec2 dx = vec2(uSoftness, 0.0);
  vec2 dy = vec2(0.0, uSoftness);
  vec4 color = backdrop(samplePoint) * 0.25;
  color += (backdrop(samplePoint + dx) + backdrop(samplePoint - dx)
          + backdrop(samplePoint + dy) + backdrop(samplePoint - dy)) * 0.125;
  color += (backdrop(samplePoint + dx + dy) + backdrop(samplePoint + dx - dy)
          + backdrop(samplePoint - dx + dy) + backdrop(samplePoint - dx - dy)) * 0.0625;
  fragColor = color;
}
