///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
in vec3 a_position;
in vec2 a_texcoord0;

out vec2 v_texcoord0;

void main() {
    v_texcoord0 = a_texcoord0;
    gl_Position = vec4(a_position.xy * 2.0 - 1.0, 0.0, 1.0);
}
#endif

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
uniform vec4 ExposureCompensation;
uniform vec4 LuminanceMinMaxAndWhitePointAndMinWhitePoint;

SAMPLER2D(s_ColorTexture);
SAMPLER2D(s_PreExposureLuminance);
SAMPLER2D(s_AverageLuminance);
SAMPLER2D(s_CustomExposureCompensation);
SAMPLER2D(s_RasterizedColor);

#include "lib/common.glsl"

// https://iolite-engine.com/blog_posts/minimal_agx_implementation
vec3 agxDefaultContrastApprox(vec3 x) {
    vec3 x2 = x * x;
    vec3 x4 = x2 * x2;
    vec3 x6 = x4 * x2;

    return - 17.86  * x6 * x
           + 78.01  * x6
           - 126.7  * x4 * x
           + 92.06  * x4
           - 28.72  * x2 * x
           + 4.361  * x2
           - 0.1718 * x
           + 0.002857;
}

vec3 agx(vec3 val) {
    const float min_ev = -12.47393;
    const float max_ev = 4.026069;

    const mat3 agx_mat = mat3(
        0.842479062253094, 0.0423282422610123, 0.0423756549057051,
        0.0784335999999992, 0.878468636469772, 0.0784336,
        0.0792237451477643, 0.0791661274605434, 0.879142973793104
    );

    const mat3 agx_mat_inv = mat3(
        1.19687900512017, -0.0528968517574562, -0.0529716355144438,
        -0.0980208811401368, 1.15190312990417, -0.0980434501171241,
        -0.0990297440797205, -0.0989611768448433, 1.15107367264116
    );

    val = agx_mat * val;

    val = clamp(log2(val), min_ev, max_ev);
    val = (val - min_ev) / (max_ev - min_ev);
    val = agxDefaultContrastApprox(val);

    val = agx_mat_inv * val;
    return val;
}

in vec2 v_texcoord0;
out vec4 fragColor;

void main() {
    vec3 inputColor = texture(s_ColorTexture, v_texcoord0).rgb;
    inputColor = unExposeLighting(inputColor, texture(s_PreExposureLuminance, vec2(0.5)).r);

    float refLuminance = clamp(texture(s_AverageLuminance, vec2(0.5)).r,
        LuminanceMinMaxAndWhitePointAndMinWhitePoint.r,
        LuminanceMinMaxAndWhitePointAndMinWhitePoint.g);
    float exposure = (MIDDLE_GRAY / refLuminance) * ExposureCompensation.g;
    inputColor *= exposure;

    vec4 overlayCol = texture(s_RasterizedColor, v_texcoord0);
    inputColor = mix(inputColor, overlayCol.rgb, overlayCol.a);

    vec3 outColor = agx(inputColor);
    fragColor = vec4(outColor, 1.0);
}
#endif //SHADER_STAGE__FRAGMENT
