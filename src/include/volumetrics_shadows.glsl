#if THREAD_LIMIT__LIMITED_AT128
layout(local_size_x = 8, local_size_y = 8, local_size_z = 2) in;
#endif
#if THREAD_LIMIT__LIMITED_AT256
layout(local_size_x = 8, local_size_y = 8, local_size_z = 4) in;
#endif
#if THREAD_LIMIT__NATIVE
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
#endif

uniform mat4 CascadesShadowProj[8];
uniform mat4 PlayerShadowProj;
uniform vec4 CascadesParameters[8];
uniform vec4 CascadesPerSet;
uniform vec4 FirstPersonPlayerShadowsEnabledAndResolutionAndFilterWidthAndTextureDimensions;
uniform vec4 JitterOffset;
uniform vec4 TemporalSettings;
uniform vec4 VolumeDimensions;
uniform vec4 VolumeNearFar;
uniform mat4 u_invViewProj;
uniform mat4 u_proj;
uniform mat4 u_viewProj;
uniform mat4 u_invProj;
uniform vec4 u_prevWorldPosOffset;

SAMPLER2DARRAY(s_ShadowCascades);
SAMPLER2DARRAY(s_PreviousCascadedShadowBuffer);
IMAGE2D_ARRAY_WO(s_CascadedShadowBufferOut, r32f);

#include "lib/froxel_utils.glsl"

float calcFPShadow(vec3 worldPos) {
    vec3 projPos = (PlayerShadowProj * vec4(worldPos, 1.0)).xyz;
    projPos.z = min(projPos.z, 1.0);

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
    return step(occluder, textureLod(s_ShadowCascades, vec3(uvShadow, cascade), 0.0).r);
}

int getCascade(vec3 worldPos, out vec3 projPos) {
    int numShadow = 0;
    int numCascade = int(dot(clamp(CascadesPerSet, 0.0, 1.0), vec4(1.0)));

    for (int i = 0; i < numCascade; i++) {
        int cascadePerSet = min(int(CascadesPerSet[i]), 8 - numShadow);
        for (int j = 0; j < cascadePerSet; j++) {
            int cascadeIdx = numShadow + j;
            projPos = (CascadesShadowProj[cascadeIdx] * vec4(worldPos, 1.0)).xyz;
            if (all(lessThanEqual(abs(projPos), vec3(1.0)))) return cascadeIdx;
        }
        numShadow += cascadePerSet;
    }

    return -1;
}

float calcTShadow(vec3 worldPos) {
    vec3 projPos;
    int cascade = getCascade(worldPos, projPos);
    if (cascade < 0) return 1.0;

#if TRANSPILE_TARGET__GLSL
    vec2 uvShadow = projPos.xy * 0.5 + 0.5;
    float occluder = projPos.z * 0.5 + 0.5;
#else
    vec2 uvShadow = vec2(projPos.x, -projPos.y) * 0.5 + 0.5;
    float occluder = projPos.z;
#endif

    float shadowScale = CascadesParameters[cascade].x;
    uvShadow = uvShadow * shadowScale + vec2(0.0, 1.0 - shadowScale);
    return step(occluder, textureLod(s_ShadowCascades, vec3(uvShadow, cascade), 0.0).r);
}

void main() {
    uvec3 xyz = gl_GlobalInvocationID;
    if (any(greaterThanEqual(xyz, uvec3(VolumeDimensions.xyz)))) return;

    vec3 uvw = (vec3(xyz) + JitterOffset.xyz + 0.5) / VolumeDimensions.xyz;
    vec3 worldPos = volumeToWorld(VolumeNearFar.xy, uvw, u_invViewProj, u_proj);

    vec3 uvwNoJitt = (vec3(xyz) + 0.5) / VolumeDimensions.xyz;
    vec3 worldPosNoJitt = volumeToWorld(VolumeNearFar.xy, uvwNoJitt, u_invViewProj, u_proj);
    vec3 prevUvw = worldToVolume(
        VolumeNearFar.xy,
        worldPosNoJitt - u_prevWorldPosOffset.xyz,
        u_viewProj,
        u_invProj
    );

    float shadowMap = calcTShadow(worldPos);
    float fpShadow = calcFPShadow(worldPos);
    shadowMap = min(shadowMap, fpShadow);

    vec4 prevValue = sampleVolume(s_PreviousCascadedShadowBuffer, prevUvw,
        VolumeDimensions.z);

    vec3 prevTexel = VolumeDimensions.xyz * prevUvw;
    vec3 prevTexelClamped = clamp(prevTexel, vec3(0.0), VolumeDimensions.xyz);
    float distBoundary = distance(prevTexelClamped, prevTexel);
    float rejectH = clamp(distBoundary * TemporalSettings.y, 0.0, 1.0);
    float blendW = mix(TemporalSettings.z, 0.0, rejectH);

    if (TemporalSettings.x > 0.0)
        imageStore(s_CascadedShadowBufferOut, ivec3(xyz),
            vec4(mix(shadowMap, prevValue.r, blendW), 0.0, 0.0, 0.0));
    else
        imageStore(s_CascadedShadowBufferOut, ivec3(xyz), vec4(shadowMap, 0.0, 0.0, 0.0));
}
