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

// https://www.shadertoy.com/view/dtSGD1
const mat3 SRGB_TO_ADJUSTED = mat3(
    0.9211994645, 0.0211994645, 0.0211994645,
    0.0392150826, 0.9392150826, 0.0392150826,
    0.0395854529, 0.0395854529, 0.9395854529
);

const mat3 ADJUSTED_TO_SRGB = mat3(
    1.0875561505, -0.0235549606, -0.0235549606,
    -0.0435723139, 1.0675387972, -0.0435723139,
    -0.0439838366, -0.0439838366, 1.0671272745
);

vec3 openDomainToNormalizedLog2(vec3 openDomain) {
    const float min_ev = -10.0;
    const float max_ev = 6.5;

    float total_exposure = max_ev - min_ev;
    vec3 output_log = clamp(log2(openDomain / MIDDLE_GRAY), min_ev, max_ev);
    return (output_log - min_ev) / total_exposure;
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

    vec4 overlayCol = texture(s_RasterizedColor, v_texcoord0);
    inputColor = mix(inputColor, overlayCol.rgb, overlayCol.a);

    vec3 outColor = SRGB_TO_ADJUSTED * inputColor;
    outColor = max(outColor, vec3(1e-6));
    outColor = openDomainToNormalizedLog2(outColor);
    outColor = agxCurve3(outColor);
    outColor = ADJUSTED_TO_SRGB * outColor;

    outColor = clamp(outColor, 0.0, 1.0);

    fragColor = vec4(outColor, 1.0);
}
#endif //SHADER_STAGE__FRAGMENT
