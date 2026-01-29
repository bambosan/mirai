#if BGFX_SHADER_TYPE_VERTEX
void main() {
    gl_Position = vec4(a_position.xy * 2.0 - 1.0, 0.0, 1.0);
    v_texcoord0 = a_texcoord0;
}
#endif

#if BGFX_SHADER_TYPE_FRAGMENT
uniform highp vec4 TonemapParams0;
uniform highp vec4 ExposureCompensation;
uniform highp vec4 LuminanceMinMaxAndWhitePointAndMinWhitePoint;

SAMPLER2D_HIGHP_AUTOREG(s_ColorTexture);
SAMPLER2D_HIGHP_AUTOREG(s_PreExposureLuminance);
SAMPLER2D_HIGHP_AUTOREG(s_AverageLuminance);
SAMPLER2D_HIGHP_AUTOREG(s_CustomExposureCompensation);
SAMPLER2D_HIGHP_AUTOREG(s_RasterizedColor);

#include "./lib/common.glsl"

//https://github.com/bWFuanVzYWth/AgX
vec3 agx_curve3(vec3 v) {
    CONST(float) threshold = 0.6060606060606061;
    CONST(float) a_up = 69.86278913545539;
    CONST(float) a_down = 59.507875;
    CONST(float) b_up = 13.0 / 4.0;
    CONST(float) b_down = 3.0 / 1.0;
    CONST(float) c_up = -4.0 / 13.0;
    CONST(float) c_down = -1.0 / 3.0;

    vec3 mask = step(v, vec3_splat(threshold));
    vec3 a = a_up + (a_down - a_up) * mask;
    vec3 b = b_up + (b_down - b_up) * mask;
    vec3 c = c_up + (c_down - c_up) * mask;
    return 0.5 + (((-2.0 * threshold)) + 2.0 * v) * pow(1.0 + a * pow(abs(v - threshold), b), c);
}

vec3 agx_tonemapping(vec3 ci) {
    CONST(float) min_ev = -12.473931188332413;
    CONST(float) max_ev = 4.026068811667588;
    CONST(float) dynamic_range = max_ev - min_ev;

    mat3 agx_mat = mtxFromCols(
        vec3(0.8424010709504686, 0.04240107095046854, 0.04240107095046854),
        vec3(0.07843650156180276, 0.8784365015618028, 0.07843650156180276),
        vec3(0.0791624274877287, 0.0791624274877287, 0.8791624274877287)
    );
    mat3 agx_mat_inv = mtxFromCols(
        vec3(1.1969986613119143, -0.053001338688085674, -0.053001338688085674),
        vec3(-0.09804562695225345, 1.1519543730477466, -0.09804562695225345),
        vec3(-0.09895303435966087, -0.09895303435966087, 1.151046965640339)
    );

    // Input transform (inset)
    ci = mul(agx_mat, ci);

    // Apply sigmoid function
    vec3 ct = saturate(log2(ci) * (1.0 / dynamic_range) - (min_ev / dynamic_range));
    vec3 co = agx_curve3(ct);

    // i need more saturation
    co = saturation(co, 1.2);

    // Inverse input transform (outset)
    co = mul(agx_mat_inv, co);

    return co;
}

//https://www.shadertoy.com/view/wdtfRS
vec3 SoftClip(vec3 x) {
    return (1.0 + x - sqrt(1.0 - 1.99*x + x*x)) / (1.995);
}

void main() {
    vec3 inputColor = texture2D(s_ColorTexture, v_texcoord0).rgb;
    inputColor = max(inputColor, vec3_splat(0.0));

    // from deobfuscated vanilla materials, currently just leave it there
    if (TonemapParams0.b > 0.0) {
        float preExposureLum = texture2D(s_PreExposureLuminance, vec2_splat(0.5)).r;
        inputColor = inputColor / vec3_splat((MIDDLE_GRAY / preExposureLum) + 0.0001);
    }
    float refLuminance = MIDDLE_GRAY;
    if (ExposureCompensation.b > 0.5) {
        float avgLum = texture2D(s_AverageLuminance, vec2_splat(0.5)).r;
        refLuminance = clamp(avgLum, LuminanceMinMaxAndWhitePointAndMinWhitePoint.r, LuminanceMinMaxAndWhitePointAndMinWhitePoint.g);
    }
    int exposureMode = int(ExposureCompensation.r);
    float exposureValue = ExposureCompensation.g; //manual
    if (exposureMode > 0 && exposureMode < 2) {
        //automatic
        exposureValue = 1.03 - (2.0 / ((0.43429 * log(refLuminance + 1.0)) + 2.0));
    } else if (exposureMode > 1) {
        //custom
        float lumMin = LuminanceMinMaxAndWhitePointAndMinWhitePoint.r;
        float lumMax = LuminanceMinMaxAndWhitePointAndMinWhitePoint.g;
        float t = (lumMin == lumMax) ? 0.5 : ((log2(refLuminance) + 3.0) - (log2(lumMin) + 3.0)) / ((log2(lumMax) + 3.0) - (log2(lumMin) + 3.0));
        exposureValue = texture2D(s_CustomExposureCompensation, vec2(t, 0.5)).r;
    }

    float exposureScale = (MIDDLE_GRAY / refLuminance) * exposureValue;
    vec3 outColor = agx_tonemapping(inputColor * exposureScale);
    outColor = SoftClip(outColor);

    vec4 rasterColor = texture2D(s_RasterizedColor, v_texcoord0);
    rasterColor.rgb = pow(rasterColor.rgb, vec3_splat(1.0 / 2.2));
    outColor = mix(outColor, rasterColor.rgb, rasterColor.a);

    gl_FragColor = vec4(outColor, 1.0);
}
#endif
