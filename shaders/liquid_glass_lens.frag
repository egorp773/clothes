#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

out vec4 fragColor;

uniform vec2 u_size;
uniform sampler2D u_texture;
uniform float u_strength;
uniform float u_edgeLight;

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif

  vec2 position = uv * 2.0 - 1.0;
  vec2 absolutePosition = abs(position);
  float edgeDistance = max(absolutePosition.x, absolutePosition.y);
  float lens = smoothstep(0.48, 0.985, edgeDistance);

  vec2 edgeNormal = absolutePosition.x > absolutePosition.y
      ? vec2(sign(position.x), 0.0)
      : vec2(0.0, sign(position.y));
  float displacement = (0.0035 + 0.0085 * u_strength) * pow(lens, 1.65);
  vec2 refractedUv = clamp(uv - edgeNormal * displacement, 0.001, 0.999);

  vec4 centerSample = texture(u_texture, refractedUv);
  vec2 scatterOffset = edgeNormal * (0.0011 * lens * u_strength);
  vec3 innerSample = texture(
    u_texture,
    clamp(refractedUv - scatterOffset, 0.001, 0.999)
  ).rgb;
  vec3 outerSample = texture(
    u_texture,
    clamp(refractedUv + scatterOffset, 0.001, 0.999)
  ).rgb;
  vec3 scatteredColor = (innerSample + outerSample) * 0.5;
  vec3 refractedColor = mix(
    centerSample.rgb,
    scatteredColor,
    0.12 * lens * u_strength
  );

  vec2 lightDirection = normalize(vec2(-0.72, -0.68));
  float facingLight = max(dot(-edgeNormal, lightDirection), 0.0);
  float specular = pow(facingLight, 7.0) * pow(lens, 3.2) * u_edgeLight;
  refractedColor += vec3(specular * 0.055);

  fragColor = vec4(refractedColor, centerSample.a);
}
