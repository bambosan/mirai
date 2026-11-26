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

const float PURKINJE_LUM_MIN = -4.0;
const float PURKINJE_LUM_MAX = 4.0;
const float PURKINJE_FADE_END = -0.5;
const float PURKINJE_STRENGTH = 1.0;
const float PURKINJE_CURVE = 2.0;
const float PURKINJE_PIXEL_DARK_EV = -4.0;
const float PURKINJE_PIXEL_BRIGHT_EV = -0.5;

const vec3 SCOTOPIC_WEIGHTS = vec3(0.0, 0.62, 0.38);
const vec3 SCOTOPIC_TINT = vec3(0.55, 0.78, 1.0);

float purkinjeAdaptation(float adaptLuminance) {
    float ev = log2(max(adaptLuminance, 1e-5));
    float fadeEnd = min(PURKINJE_FADE_END, PURKINJE_LUM_MAX);
    float t = smoothstep(PURKINJE_LUM_MIN, fadeEnd, ev);
    return pow(1.0 - t, PURKINJE_CURVE);
}

float purkinjePixelMask(vec3 exposedColor) {
    float lum = max(dot(exposedColor, LUMA_REC709), 1e-5);
    float ev = log2(lum / MIDDLE_GRAY);
    return 1.0 - smoothstep(PURKINJE_PIXEL_DARK_EV, PURKINJE_PIXEL_BRIGHT_EV, ev);
}

vec3 applyPurkinje(vec3 color, float adaptation) {
    float amount = adaptation * purkinjePixelMask(color) * PURKINJE_STRENGTH;
    if (amount <= 0.0) return color;

    float scotopicLum = dot(color, SCOTOPIC_WEIGHTS);
    vec3 tint = SCOTOPIC_TINT / dot(SCOTOPIC_TINT, LUMA_REC709);
    vec3 rodColor = scotopicLum * tint;

    return mix(color, rodColor, amount);
}

// https://www.shadertoy.com/view/dtSGD1
const mat3 AGX_INSET = mat3(
    0.9408995984, 0.0158995984, 0.0158995984,
    0.0294113119, 0.9544113119, 0.0294113119,
    0.0296890897, 0.0296890897, 0.9546890897
);

const mat3 AGX_OUTSET = mat3(
    1.0638923261, -0.0171887550, -0.0171887550,
    -0.0317960129, 1.0492850682, -0.0317960129,
    -0.0320963132, -0.0320963132, 1.0489847679
);

const float AGX_MIN_EV = -10.0;
const float AGX_MAX_EV = 6.5;

vec3 openDomainToNormalizedLog2(vec3 openDomain) {
    float total_exposure = AGX_MAX_EV - AGX_MIN_EV;
    vec3 output_log = clamp(log2(openDomain / MIDDLE_GRAY), AGX_MIN_EV, AGX_MAX_EV);
    return (output_log - AGX_MIN_EV) / total_exposure;
}

// https://github.com/bWFuanVzYWth/AgX
vec3 agxCurve3(vec3 v) {
    const float threshold = 0.6060606060606061;
    const float slope = 2.3;
    const float a_up = 95.42903416;
    const float a_down = 15.57566596;
    const float b_up = 3.1;
    const float b_down = 1.9;
    const float c_up = -1.0 / 3.1;
    const float c_down = -1.0 / 1.9;

    vec3 mask = step(v, vec3(threshold));
    vec3 a = mix(vec3(a_up), vec3(a_down), mask);
    vec3 b = mix(vec3(b_up), vec3(b_down), mask);
    vec3 c = mix(vec3(c_up), vec3(c_down), mask);
    return 0.5 + slope * (v - threshold) * pow(1.0 + a * pow(abs(v - threshold), b), c);
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

    inputColor = applyPurkinje(inputColor, purkinjeAdaptation(refLuminance));

    vec4 overlayCol = texture(s_RasterizedColor, v_texcoord0);
    inputColor = mix(inputColor, overlayCol.rgb, overlayCol.a);

    vec3 outColor = AGX_INSET * inputColor;
    outColor = max(outColor, vec3(1e-5));
    outColor = openDomainToNormalizedLog2(outColor);
    outColor = agxCurve3(outColor);
    outColor = AGX_OUTSET * outColor;

    outColor = clamp(outColor, 0.0, 1.0);

    fragColor = vec4(outColor, 1.0);
}
#endif //SHADER_STAGE__FRAGMENT
