#version 440
// Chladni plate: W = sum_i a_i R_i(r) cos(n_i theta), R_i from the engine's eigenmode LUT
// (free-edge circular plate, solved in engine/plate.py). Sand where |W| is small.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float aspect;
    float energy;     // measured loudness 0..1 (line sharpness, sand agitation)
    float hit;        // recent taal hit 0..1 (grain jump)
    float count;      // number of modes in the LUT (rows)
    float pad0;
    float pad1;
    float pad2;
    vec4 colL;
    vec4 colR;
    vec4 colF;
    vec4 a0; vec4 a1; vec4 a2; vec4 a3; vec4 a4; vec4 a5; vec4 a6;   // mode amplitudes 0..1 (28 slots)
    vec4 n0; vec4 n1; vec4 n2; vec4 n3; vec4 n4; vec4 n5; vec4 n6;   // nodal-diameter counts per mode
} u;
layout(binding = 1) uniform sampler2D lut;

float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }

void main() {
    vec2 uv = qt_TexCoord0 * 2.0 - 1.0;
    uv.x *= u.aspect;
    float r = length(uv);
    float th = atan(uv.y, uv.x);
    vec4 A[7] = vec4[7](u.a0, u.a1, u.a2, u.a3, u.a4, u.a5, u.a6);
    vec4 N[7] = vec4[7](u.n0, u.n1, u.n2, u.n3, u.n4, u.n5, u.n6);
    float W = 0.0, norm = 0.0;
    int cnt = int(u.count);
    for (int i = 0; i < 28; i++) {
        if (i >= cnt) break;
        float a = A[i >> 2][i & 3];
        if (a < 0.003) continue;
        float n = N[i >> 2][i & 3];
        float R = texture(lut, vec2(clamp(r, 0.0, 1.0), (float(i) + 0.5) / u.count)).r * 2.0 - 1.0;
        W += a * R * cos(n * th);
        norm += a;
    }
    W /= max(norm, 1e-4);
    // louder plate → sand thrown harder → it collects in tighter lines
    float sigma = mix(0.16, 0.035, clamp(u.energy, 0.0, 1.0));
    float sand = exp(-(W * W) / (2.0 * sigma * sigma));
    float grain = hash(floor(uv * 300.0) + floor(u.time * (4.0 + 20.0 * u.hit)));
    sand *= (0.5 + 0.5 * grain) * (norm > 0.003 ? 1.0 : 0.0);
    float inPlate = smoothstep(1.005, 0.995, r);
    float rim = smoothstep(0.98, 0.995, r) * (1.0 - smoothstep(1.0, 1.02, r));
    vec3 B = u.colF.rgb;
    vec3 plateCol = B * 1.35 + 0.015;
    vec3 sandCol = mix(u.colL.rgb, u.colR.rgb, clamp(0.5 + 0.5 * W, 0.0, 1.0));
    vec3 col = mix(B, plateCol, inPlate);
    col = mix(col, sandCol, sand * inPlate * (0.6 + 0.4 * u.energy));
    col += rim * 0.2 * u.colL.rgb;
    fragColor = vec4(col, 1.0) * u.qt_Opacity;
}
