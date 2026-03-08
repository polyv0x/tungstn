#include <flutter/runtime_effect.glsl>

// Blob positions passed from CPU (pixel-space), computed once per frame with
// cheap sin/cos on the Dart side so the GPU only does arithmetic per fragment.
uniform vec2 uSize;
uniform vec2 uB0;
uniform vec2 uB1;
uniform vec2 uB2;
uniform vec2 uB3;
uniform vec2 uB4;
uniform vec2 uB5;

out vec4 fragColor;

// Classic metaball potential: r² / d²  (higher = closer to center)
float field(vec2 p, vec2 c, float r2) {
    vec2 d = p - c;
    return r2 / max(dot(d, d), 1.0);
}

void main() {
    vec2 p = FlutterFragCoord().xy;

    // Scale radius with screen height so blobs look the same on any screen size
    float scale = uSize.y * uSize.y;

    float sum = 0.0;
    sum += field(p, uB0, 0.0400 * scale);
    sum += field(p, uB1, 0.0324 * scale);
    sum += field(p, uB2, 0.0272 * scale);
    sum += field(p, uB3, 0.0300 * scale);
    sum += field(p, uB4, 0.0256 * scale);
    sum += field(p, uB5, 0.0280 * scale);

    // Smooth threshold creates the "merge" effect
    float fill  = smoothstep(0.78, 1.08, sum);
    float inner = smoothstep(1.08, 2.50, sum);
    float glow  = smoothstep(0.28, 0.78, sum) * (1.0 - fill);

    // Blurple palette — dark bg to vivid violet/blue
    vec3 bg    = vec3(0.050, 0.028, 0.118);
    vec3 rimC  = vec3(0.30,  0.19,  0.72);
    vec3 midC  = vec3(0.43,  0.29,  0.90);
    vec3 coreC = vec3(0.62,  0.52,  1.00);

    vec3 col = bg;
    col = mix(col, rimC,  fill);
    col = mix(col, midC,  inner * 0.70);
    col = mix(col, coreC, inner * inner * 0.50);
    col += glow * rimC * 0.18;   // subtle outer halo

    fragColor = vec4(col, 1.0);
}
