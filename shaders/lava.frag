#version 440
// Lava — metaballs with thermal colour, same field function as visual.js drawLava.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float thr;       // 1 - breath*0.25
    float aspect;
    float pad0;
    float pad1;
    vec4 colL;
    vec4 colR;
    vec4 colF;
    vec4 b0; vec4 b1; vec4 b2; vec4 b3; vec4 b4; vec4 b5; vec4 b6; vec4 b7; vec4 b8; vec4 b9;  // x, y (160 x FH units), r, T
} u;
void main() {
    float FW = 160.0;
    float FH = FW / max(0.1, u.aspect);
    float x = qt_TexCoord0.x * FW;
    float y = qt_TexCoord0.y * FH;
    float f = 0.0, tw = 0.0;
    vec4 bl[10] = vec4[10](u.b0, u.b1, u.b2, u.b3, u.b4, u.b5, u.b6, u.b7, u.b8, u.b9);
    for (int i = 0; i < 10; i++) {
        vec4 b = bl[i];
        float dx = x - b.x, dy = y - b.y;
        float q = b.z * b.z / (dx * dx + dy * dy + 0.5);
        f += q; tw += q * b.w;
    }
    float T = f > 0.0 ? tw / f : 0.0;
    float edge = clamp((f - u.thr * 0.75) / (u.thr * 0.25), 0.0, 1.0);
    float a, c, g;
    if (f > u.thr) { a = T; c = 1.0 - T; g = 1.0; } else { a = T * edge; c = (1.0 - T) * edge; g = 0.55 * edge; }
    vec3 B = u.colF.rgb;
    vec3 col = B + a * (u.colL.rgb - B) * g + c * (u.colR.rgb - B) * g;
    fragColor = vec4(col, 1.0) * u.qt_Opacity;
}
