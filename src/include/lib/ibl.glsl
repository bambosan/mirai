#ifndef IBL_INCLUDED
#define IBL_INCLUDED

#include "common.glsl"

SAMPLER2D(s_BrdfLUT);
SAMPLERCUBEARRAY(s_SpecularIBLRecords);

float calcIBLMipLevel(float a, float b, float convType) {
    float x = 1.0 - a;
    if (int(convType) != 1) x = pow(x, 4.0);
    return (1.0 - x * x) * (b - 1.0);
}

vec3 calcProbeLighting(
    vec4 iblParams,
    vec3 rv,
    float a,
    float convType,
    float lastSpecIdx
) {
    float iblMipLevel = calcIBLMipLevel(a, iblParams.g, convType);
    int curr = int(lastSpecIdx);
    int prev = (curr + 2) % 3;
    vec3 preFilteredCol = mix(
        textureLod(s_SpecularIBLRecords, vec4(rv, prev), iblMipLevel).rgb,
        textureLod(s_SpecularIBLRecords, vec4(rv, curr), iblMipLevel).rgb,
        iblParams.a
    );
    return preFilteredCol * iblParams.b;
}

#if DO_INDIRECT_SPECULAR_SHADING_PASS
SAMPLER2D(s_SSRTexture);

vec3 indirectSpecular(
    vec4 iblParams,
    vec4 ssrParams,
    vec3 f0,
    vec3 worldDir,
    vec3 normal,
    vec2 ssrUV,
    float convType,
    float lastSpecIdx,
    float roughness,
    float occluder,
    float exposure
) {
    vec3 ilight = vec3(0.0);

    if (iblParams.r > 0.0) {
        vec3 reflectedDir = reflect(worldDir, normal);
        vec3 skyProbe = calcProbeLighting(
            iblParams,
            reflectedDir,
            roughness,
            convType,
            lastSpecIdx
        );
        ilight = skyProbe * occluder * (1.0 - roughness);

        vec4 ssr = texture(s_SSRTexture, ssrUV);
        ssr.rgb = unExposeLighting(ssr.rgb * (1.0 / EXPOSURE_MULTIPLIER), exposure);
        if (ssrParams.r > 0.0)
            ilight = mix(ilight, ssr.rgb, ssr.a * ssrParams.g);
    }

    float cost = clamp(dot(-worldDir, normal), 0.0, 1.0);
    vec2 envDFG = texture(s_BrdfLUT, vec2(cost, 1.0 - roughness)).rg;
    return ilight * (f0 * envDFG.r + envDFG.g);
}

#else

vec3 indirectSpecular(
    vec4 iblParams,
    vec3 f0,
    vec3 worldDir,
    vec3 normal,
    float convType,
    float lastSpecIdx,
    float roughness,
    float occluder
) {
    vec3 ilight = vec3(0.0);

    if (iblParams.r > 0.0) {
        vec3 reflectedDir = reflect(worldDir, normal);
        vec3 skyProbe = calcProbeLighting(
            iblParams,
            reflectedDir,
            roughness,
            convType,
            lastSpecIdx
        );
        ilight = skyProbe * occluder * (1.0 - roughness);
    }

    float cost = clamp(dot(-worldDir, normal), 0.0, 1.0);
    vec2 envDFG = texture(s_BrdfLUT, vec2(cost, 1.0 - roughness)).rg;
    return ilight * (f0 * envDFG.r + envDFG.g);
}
#endif
#endif
