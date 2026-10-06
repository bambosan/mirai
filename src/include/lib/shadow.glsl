#ifndef SHADOW_INCLUDED
#define SHADOW_INCLUDED

uniform mat4 CascadesShadowInvProj[8];
uniform mat4 CascadesShadowProj[8];
uniform mat4 PlayerShadowProj;
uniform vec4 CascadesParameters[8];
uniform vec4 CascadesPerSet;
uniform vec4 DirectionalLightSourceShadowDirection;
uniform vec4 FirstPersonPlayerShadowsEnabledAndResolutionAndFilterWidthAndTextureDimensions;
uniform vec4 NdLFloor;
uniform vec4 ShadowFilterOffsetAndRangeFarAndMapSizeAndNormalOffsetStrength;

SAMPLER2DARRAY(s_ShadowCascades);

const vec2 PCF_OFFSETS[4] = vec2[](
    vec2(-0.5, -0.5),
    vec2(0.5, -0.5),
    vec2(-0.5, 0.5),
    vec2(0.5, 0.5)
);

float bilinearPCF(vec4 samples, vec2 weights, float compValue) {
    vec4 comp = step(compValue, samples);
    return mix(mix(comp.w, comp.z, weights.x), mix(comp.x, comp.y, weights.x), weights.y);
}

float bilinearTsm(vec4 samples, vec2 weights, float compValue, float falloff) {
    vec4 comp = clamp(exp(-(compValue - samples) * falloff), 0.0, 1.0);
    return mix(mix(comp.w, comp.z, weights.x), mix(comp.x, comp.y, weights.x), weights.y);
}

float calcFPShadow(vec3 worldPos, float nDotSd) {
    float slopeMask = clamp(nDotSd, NdLFloor.r, 1.0);
    float zbias = CascadesParameters[0].g
        + CascadesParameters[0].b * (sqrt(1.0 - (slopeMask * slopeMask)) / slopeMask);

    vec3 projPos = (PlayerShadowProj * vec4(worldPos, 1.0)).xyz;
    projPos.z = min(projPos.z - zbias, 1.0);

#if TRANSPILE_TARGET__GLSL
    vec2 uvShadow = projPos.xy * 0.5 + 0.5;
    float occluder = projPos.z * 0.5 + 0.5;
#else
    vec2 uvShadow = vec2(projPos.x, -projPos.y) * 0.5 + 0.5;
    float occluder = projPos.z;
#endif

    float shadowScale =
        FirstPersonPlayerShadowsEnabledAndResolutionAndFilterWidthAndTextureDimensions.g;
    uvShadow *= shadowScale;

    bool isShadowFrustum = all(greaterThanEqual(uvShadow, vec2(0.0)))
        && all(lessThan(uvShadow, vec2(shadowScale)));
    if (!isShadowFrustum) return 1.0;

#if TRANSPILE_TARGET__GLSL
    uvShadow.y += 1.0 - shadowScale;
#endif

    float cascade = dot(CascadesPerSet, vec4(1.0)) + 1.0;
    float result = 0.0;

    float offsetScale =
        FirstPersonPlayerShadowsEnabledAndResolutionAndFilterWidthAndTextureDimensions.b
        * shadowScale;

    for (int i = 0; i < 4; i++) {
        vec2 uvOffset = uvShadow + PCF_OFFSETS[i] * offsetScale;
        vec4 shadowSamples = textureGather(s_ShadowCascades, vec3(uvOffset, cascade), 0);
        vec2 weights = fract(
            uvOffset * ShadowFilterOffsetAndRangeFarAndMapSizeAndNormalOffsetStrength.b + 0.5
        );
        result += bilinearPCF(shadowSamples, weights, occluder);
    }

    return result * 0.25;
}

int calcCascade(vec3 worldPos, out vec3 projPos, out mat4 invProj) {
    int numShadow  = 0;
    int numCascade = int(dot(clamp(CascadesPerSet, 0.0, 1.0), vec4(1.0)));

    for (int i = 0; i < numCascade; i++) {
        int cascadePerSet = min(int(CascadesPerSet[i]), 8 - numShadow);
        for (int j = 0; j < cascadePerSet; j++) {
            int cascadeIdx = numShadow + j;
            projPos = (CascadesShadowProj[cascadeIdx] * vec4(worldPos, 1.0)).xyz;
            invProj = CascadesShadowInvProj[cascadeIdx];

            if (all(lessThanEqual(abs(projPos), vec3(1.0)))) return cascadeIdx;
        }
        numShadow += cascadePerSet;
    }

    return -1;
}

vec2 calcTShadow(vec3 worldPos, float nDotSd) {
    vec3 projPos;
    mat4 invProj;
    int cascade = calcCascade(worldPos, projPos, invProj);
    if (cascade < 0) return vec2(1.0);

    float falloff = length(invProj[2].xyz) * 5.0;

    float slopeMask = clamp(nDotSd, NdLFloor[cascade], 1.0);
    float zbias = CascadesParameters[cascade].g
        + CascadesParameters[cascade].b * (sqrt(1.0 - (slopeMask * slopeMask)) / slopeMask);
    projPos.z -= zbias;

#if TRANSPILE_TARGET__GLSL
    vec2 uvShadow = projPos.xy * 0.5 + 0.5;
    float occluder = projPos.z * 0.5 + 0.5;
#else
    vec2 uvShadow = vec2(projPos.x, -projPos.y) * 0.5 + 0.5;
    float occluder = projPos.z;
#endif

    float shadowScale = CascadesParameters[cascade].r;
    uvShadow = uvShadow * shadowScale + vec2(0.0, 1.0 - shadowScale);

    vec2 result = vec2(0.0);
    float offsetScale =
        ShadowFilterOffsetAndRangeFarAndMapSizeAndNormalOffsetStrength.r * shadowScale;

    for (int i = 0; i < 4; i++) {
        vec2 uvOffset = uvShadow + PCF_OFFSETS[i] * offsetScale;
        vec4 shadowSamples = textureGather(s_ShadowCascades, vec3(uvOffset, cascade), 0);
        vec2 weights = fract(
            uvOffset * ShadowFilterOffsetAndRangeFarAndMapSizeAndNormalOffsetStrength.b + 0.5
        );
        result.x += bilinearPCF(shadowSamples, weights, occluder);
        result.y += bilinearTsm(shadowSamples, weights, occluder, falloff);
    }

    return result * 0.25;
}

vec2 calcShadowMap(vec3 worldPos, vec3 normal) {
    float nDotSd = clamp(dot(DirectionalLightSourceShadowDirection.xyz, normal), 0.0, 1.0);
    float offsetStrength =
        ShadowFilterOffsetAndRangeFarAndMapSizeAndNormalOffsetStrength.a * (1.0 - nDotSd);
    vec3 biasedWPos = worldPos + normal * offsetStrength;

    vec2 shadowMap = calcTShadow(biasedWPos, nDotSd);
    float fpShadow = calcFPShadow(biasedWPos, nDotSd);
    shadowMap.r = min(shadowMap.r, fpShadow);
    return shadowMap;
}

#endif
