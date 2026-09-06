#version 440
// Tunnel: MilkDrop-style radial tunnel — depth scrolls at the beat, ring brightness from the
// spectrum (bass near, treble far), kaleidoscope twist from mid energy.
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
    float mid;
    vec4 colL;
    vec4 colR;
    vec4 colF;
    vec4 s0; vec4 s1; vec4 s2; vec4 s3; vec4 s4; vec4 s5; vec4 s6; vec4 s7;
} u;
float band(int i) { vec4 S[8] = vec4[8](u.s0, u.s1, u.s2, u.s3, u.s4, u.s5, u.s6, u.s7); return S[i >> 2][i & 3]; }
void main() {
    vec2 uv = qt_TexCoord0 * 2.0 - 1.0; uv.x *= u.aspect;
    float r = max(length(uv), 0.02);
    float th = atan(uv.y, uv.x) + u.mid * 2.0 * sin(u.time * 0.3) + u.beatPhase * 0.25;
    float depth = 1.0 / r;                                    // tunnel coordinate
    float z = depth * 0.35 + u.time * 0.6 + u.beatPhase * 0.3;
    float wall = 0.5 + 0.5 * cos(th * 8.0 + z * 0.5);        // 8 twisting struts
    float rings = 0.5 + 0.5 * cos(z * 6.2831853);            // ring stripes scrolling toward you
    float bi = clamp((1.0 - r) * 31.0, 0.0, 31.0);           // near = bass, far = treble
    int i0 = int(floor(bi)); float v = mix(band(i0), band(min(31, i0 + 1)), fract(bi));
    float lit = (rings * 0.6 + wall * 0.4) * (0.15 + 0.85 * v) * (0.4 + 0.6 * u.energy);
    lit *= smoothstep(0.0, 0.15, r);                         // dark centre
    lit += u.hit * 0.3 * rings;
    vec3 c = mix(u.colL.rgb, u.colR.rgb, wall);
    vec3 col = mix(u.colF.rgb, c, clamp(lit, 0.0, 1.0));
    fragColor = vec4(col, 1.0) * u.qt_Opacity;
}
