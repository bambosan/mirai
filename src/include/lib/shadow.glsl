#ifndef SHADOW_INCLUDE
#define SHADOW_INCLUDE

// deobfuscated from vanilla material

uniform highp mat4 CascadesShadowInvProj[8];
uniform highp mat4 CascadesShadowProj[8];
uniform highp mat4 PlayerShadowProj;
uniform highp vec4 CascadesParameters[8];
uniform highp vec4 CascadesPerSet;
uniform highp vec4 DirectionalLightSourceShadowDirection;
uniform highp vec4 FirstPersonPlayerShadowsEnabledAndResolutionAndFilterWidthAndTextureDimensions;
uniform highp vec4 NdLFloor;
uniform highp vec4 ShadowFilterOffsetAndRangeFarAndMapSizeAndNormalOffsetStrength;

SAMPLER2DARRAY_AUTOREG(s_ShadowCascades);

float bilinearPCF(vec4 samples, vec2 weights, float compValue) {
    vec4 comp = step(compValue, samples);
    return mix(mix(comp.w, comp.z, weights.x), mix(comp.x, comp.y, weights.x), weights.y);
}

float bilinearTransmittance(vec4 samples, vec2 weights, float compValue, float falloff) {
    vec4 depth = saturate((compValue - samples) * falloff);
    vec4 comp = 1.0 - smoothstep(0.0, 1.0, depth);
    return mix(mix(comp.w, comp.z, weights.x), mix(comp.x, comp.y, weights.x), weights.y);
}

float calcFPShadow(vec3 worldPos, float nDotSd) {
    vec3 projPos = mul(PlayerShadowProj, vec4(worldPos, 1.0)).xyz;
    projPos.z = min(projPos.z, 1.0);

    float slopeMask = clamp(nDotSd, NdLFloor.r, 1.0);
    float shadowBias = CascadesParameters[0].g + CascadesParameters[0].b * (sqrt(1.0 - (slopeMask * slopeMask)) / slopeMask);

#if BGFX_SHADER_LANGUAGE_GLSL
    vec2 uvShadow = projPos.xy * 0.5 + 0.5;
    float occluder = projPos.z * 0.5 + 0.5;
    occluder -= shadowBias;
#else
    vec2 uvShadow = vec2(projPos.x, -projPos.y) * 0.5 + 0.5;
    float occluder = projPos.z - shadowBias;
#endif

    float shadowScale = FirstPersonPlayerShadowsEnabledAndResolutionAndFilterWidthAndTextureDimensions.g;
    uvShadow = uvShadow * shadowScale + vec2(0.0, 1.0 - shadowScale);

    if (uvShadow.x < 0.0 || uvShadow.x >= shadowScale || uvShadow.y < (1.0 - shadowScale) || uvShadow.y >= 1.0) return 1.0;

    float cascade = dot(CascadesPerSet, vec4_splat(1.0)) + 1.0;
    float result = 0.0;

    UNROLL
    for (int i = 0; i < 2; i++) {
        UNROLL
        for (int j = 0; j < 2; j++) {
            float y = float(i - 1) + 0.5;
            float x = float(j - 1) + 0.5;

            vec2 offsets = vec2(x, y) * FirstPersonPlayerShadowsEnabledAndResolutionAndFilterWidthAndTextureDimensions.b;
            vec2 uvOffset = uvShadow + offsets * shadowScale;

            vec4 shadowSamples = textureGather(s_ShadowCascades, vec3(uvOffset, cascade), 0);
            vec2 weights = fract(uvOffset * ShadowFilterOffsetAndRangeFarAndMapSizeAndNormalOffsetStrength.b + 0.5);
            result += bilinearPCF(shadowSamples, weights, occluder);
        }
    }

    return result * 0.25;
}

int getCascade(vec3 worldPos, out vec3 projPos, out mat4 invProj) {
    int numShadow = 0;
    int numCascade = int(dot(clamp(CascadesPerSet, 0.0, 1.0), vec4_splat(1.0)));

    LOOP
    for(int i = 0; i < numCascade; i++){
        int cascadePerSet = min(int(CascadesPerSet[i]), 8 - numShadow);
        LOOP
        for(int j = 0; j < cascadePerSet; j++){
            int cascadeIdx = numShadow + j;
            projPos = mul(CascadesShadowProj[cascadeIdx], vec4(worldPos, 1.0)).xyz;
            invProj = CascadesShadowInvProj[cascadeIdx];
            if (all(lessThanEqual(abs(projPos), vec3_splat(1.0)))) return cascadeIdx;
        }
        numShadow += cascadePerSet;
    }

    return -1;
}

vec2 calcMainShadow(vec3 worldPos, float nDotSd) {
    vec3 projPos;
    mat4 invProj;
    int cascade = getCascade(worldPos, projPos, invProj);
    if (cascade < 0) return vec2_splat(1.0);

    float slopeMask = clamp(nDotSd, NdLFloor[cascade], 1.0);
    float shadowBias = CascadesParameters[cascade].g + CascadesParameters[cascade].b * (sqrt(1.0 - (slopeMask * slopeMask)) / slopeMask);

    float falloffScale = length(invProj[2].xyz) * 2.0;

#if BGFX_SHADER_LANGUAGE_GLSL
    vec2 uvShadow = projPos.xy * 0.5 + 0.5;
    float occluder = projPos.z * 0.5 + 0.5;
    occluder -= shadowBias;
#else
    vec2 uvShadow = vec2(projPos.x, -projPos.y) * 0.5 + 0.5;
    float occluder = projPos.z - shadowBias;
#endif

    float shadowScale = CascadesParameters[cascade].r;
    uvShadow = uvShadow * shadowScale + vec2(0.0, 1.0 - shadowScale);

    vec2 result = vec2_splat(0.0);

    UNROLL
    for (int i = 0; i < 2; i++) {
        UNROLL
        for (int j = 0; j < 2; j++) {
            float y = float(i - 1) + 0.5;
            float x = float(j - 1) + 0.5;

            vec2 offsets = vec2(x, y) * ShadowFilterOffsetAndRangeFarAndMapSizeAndNormalOffsetStrength.r;
            vec2 uvOffset = uvShadow + offsets * shadowScale;

            vec4 shadowSamples = textureGather(s_ShadowCascades, vec3(uvOffset, cascade), 0);
            vec2 weights = fract(uvOffset * ShadowFilterOffsetAndRangeFarAndMapSizeAndNormalOffsetStrength.b + 0.5);

            result.x += bilinearPCF(shadowSamples, weights, occluder);
            result.y += bilinearTransmittance(shadowSamples, weights, occluder, falloffScale);
        }
    }

    return result * 0.25;
}

vec2 calcShadowMap(vec3 worldPos, vec3 normal) {
    float nDotSd = saturate(dot(DirectionalLightSourceShadowDirection.xyz, normal));
    vec3 biasedWPos = worldPos + (normal * ShadowFilterOffsetAndRangeFarAndMapSizeAndNormalOffsetStrength.a) * (1.0 - nDotSd);

    vec2 shadowMap = calcMainShadow(biasedWPos, nDotSd);
    float fpShadow = calcFPShadow(biasedWPos, nDotSd);
    shadowMap.r = min(shadowMap.r, fpShadow);
    return shadowMap;
}

#endif
