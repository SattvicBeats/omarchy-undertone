#version 440
// Mandala: the 32 measured spectrum bands folded into k-fold radial symmetry. Radius = band
// (bass at the centre), angle folded into segments, rotation locked to the measured beat phase.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float aspect;
    float energy;
    float beatPhase;
    float hit;
    float lo;
    float hi;
    float pad0;
    vec4 colL;
    vec4 colR;
    vec4 colF;
    vec4 s0; vec4 s1; vec4 s2; vec4 s3; vec4 s4; vec4 s5; vec4 s6; vec4 s7;   // 32 bands, 0..1
} u;
float band(int i) { vec4 S[8] = vec4[8](u.s0, u.s1, u.s2, u.s3, u.s4, u.s5, u.s6, u.s7); return S[i >> 2][i & 3]; }
void main() {
    vec2 uv = qt_TexCoord0 * 2.0 - 1.0; uv.x *= u.aspect;
    float r = length(uv);
    float th = atan(uv.y, uv.x) + u.beatPhase * 0.5 + u.time * 0.05;
    float k = 6.0 + floor(u.lo * 6.0);                       // more petals with more bass
    float seg = 6.2831853 / k;
    float a = abs(mod(th, seg) - seg * 0.5) / (seg * 0.5);   // 0 at petal centre, 1 at edge (mirror fold)
    // radius → band index (bass in the middle), with a petal-shaped modulation
    float rr = r * 0.95 + 0.08 * sin(a * 3.14159 * 3.0 + u.time * 0.4) * (0.5 + u.energy);
    float bi = clamp(rr * 20.0, 0.0, 31.0);
    int i0 = int(floor(bi)); int i1 = min(31, i0 + 1); float ft = fract(bi);
    float v = mix(band(i0), band(i1), ft);
    // rings: bands light their ring; petals: angular falloff
    float ring = smoothstep(0.55, 0.0, abs(fract(rr * 10.0) - 0.5)) * v;
    float petal = pow(1.0 - a, 1.5 + 4.0 * (1.0 - v));
    float lit = clamp(ring * 1.8 + petal * v * 1.3, 0.0, 1.0) * (0.5 + 0.5 * u.energy);
    lit += u.hit * 0.25 * exp(-r * 3.0);
    vec3 B = u.colF.rgb;
    vec3 c = mix(u.colL.rgb, u.colR.rgb, clamp(rr * 1.2, 0.0, 1.0));
    vec3 col = mix(B, c, lit * smoothstep(1.02, 0.9, r));
    fragColor = vec4(col, 1.0) * u.qt_Opacity;
}
