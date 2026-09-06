#version 440
// Digital cymatics: a round plate driven by the two measured ear tones. Sand (grain)
// settles where the plate is still — the nodal lines of the combined standing wave.
// Pattern is a pure function of measured frequency; nothing is assumed from settings.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float fL;         // measured strongest tone, left ear (Hz)
    float fR;         // right ear (Hz)
    float aspect;
    float energy;     // loudness 0..1
    float beatPhase;  // integral of measured (fR - fL): where the two patterns are in their beat
    float hit;        // recent taal hit 0..1
    float lo;         // bass energy
    vec4 colL;
    vec4 colR;
    vec4 colF;
} u;

float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }

// Chladni-like plate mode for frequency f at polar (r, th): radial standing wave with
// angular symmetry that rises with pitch (n nodal diameters), like a real plate.
float plate(float f, float r, float th, float twist) {
    float k = 0.030 * f + 2.0;                       // radial wavenumber grows with pitch
    float n = floor(f / 55.0 + 0.5);                 // nodal diameters: 196 Hz → 4, 440 → 8
    float radial = cos(k * r * 6.2831 * 0.25) * (1.0 / (1.0 + r * 0.6));
    float ang = cos(n * (th + twist));
    float mix2 = cos(k * r * 6.2831 * 0.25 * 0.618 + 1.3) * cos((n + 2.0) * (th - twist * 0.5));
    return radial * ang - 0.45 * mix2;
}

void main() {
    vec2 uv = qt_TexCoord0 * 2.0 - 1.0;
    uv.x *= u.aspect;
    float r = length(uv);
    float th = atan(uv.y, uv.x);
    float fL = max(u.fL, 30.0), fR = max(u.fR, 30.0);

    // two plates, one per ear, beating against each other at the measured beat
    float pL = plate(fL, r, th, 0.0);
    float pR = plate(fR, r, th, 0.3);
    float p = pL * cos(u.beatPhase * 0.5) + pR * sin(u.beatPhase * 0.5 + 0.7853);

    // sand collects where |p| is small; louder → the plate shakes harder → sharper lines
    float sigma = mix(0.35, 0.09, clamp(u.energy, 0.0, 1.0));
    float sand = exp(-(p * p) / (2.0 * sigma * sigma));
    float grain = hash(floor(uv * 260.0) + floor(u.time * 6.0) * (0.15 + u.hit)) ; // grain flickers with hits
    sand *= 0.55 + 0.45 * grain;

    // plate edge: cymatics plates are round
    float plateMask = smoothstep(1.02, 0.98, r);
    float rim = smoothstep(0.985, 0.995, r) * (1.0 - smoothstep(1.0, 1.02, r));

    vec3 B = u.colF.rgb;
    vec3 sandCol = mix(u.colL.rgb, u.colR.rgb, 0.5 + 0.5 * sin(u.beatPhase));
    vec3 plateCol = mix(B, B * 1.6 + 0.02, 0.35 + 0.25 * u.lo);        // bass warms the plate a little
    vec3 col = mix(B, plateCol, plateMask);
    col = mix(col, sandCol, sand * plateMask * (0.65 + 0.35 * u.energy));
    col += rim * 0.25 * u.colL.rgb;
    fragColor = vec4(col, 1.0) * u.qt_Opacity;
}
