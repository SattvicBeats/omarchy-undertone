#version 440
// Interference field — same formula as visual.js drawField, at native resolution.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;      // seconds
    float beat;      // Hz
    float base;      // Hz
    float aspect;    // width / height
    vec4 colL;
    vec4 colR;
    vec4 colF;
} u;
void main() {
    // work in "buffer" units: 160 px wide, height by aspect (matches the JS scale constants)
    float FW = 160.0;
    float FH = FW / max(0.1, u.aspect);
    float x = qt_TexCoord0.x * FW;
    float y = qt_TexCoord0.y * FH;
    float drift = u.time * clamp(u.beat / 10.0, 0.3, 2.0);
    float kL = 0.09 * pow(u.base / 196.0, 0.35);
    float kR = kL * (1.0 + u.beat / u.base * 40.0);
    float sx = FW * 0.32, sy = FH * 0.5;
    float r1 = length(vec2(x - sx, y - sy));
    float r2 = length(vec2(x - (FW - sx), y - sy));
    float v = (cos(kL * r1 - drift) + cos(kR * r2 + drift)) * 0.5;
    float a = max(0.0, v), c = max(0.0, -v), g = 0.15 + 0.85 * abs(v);
    vec3 B = u.colF.rgb;
    vec3 col = B + a * (u.colL.rgb - B) * g + c * (u.colR.rgb - B) * g;
    fragColor = vec4(col, 1.0) * u.qt_Opacity;
}
