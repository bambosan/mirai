#if BGFX_SHADER_TYPE_COMPUTE
uniform highp mat4 CascadesShadowInvProj[8];
uniform highp mat4 CascadesShadowProj[8];
uniform highp mat4 PlayerShadowProj;
uniform highp vec4 CascadesParameters[8];
uniform highp vec4 CascadesPerSet;
uniform highp vec4 CameraUnderwaterAndWaterSurfaceBiasAndFalloff;
uniform highp vec4 DirectionalLightSourceWorldSpaceDirection;
uniform highp vec4 FirstPersonPlayerShadowsEnabledAndResolutionAndFilterWidthAndTextureDimensions;
uniform highp vec4 FogAndDistanceControl;
uniform highp vec4 RenderChunkFogAlpha;
uniform highp vec4 HeightFogScaleBias;
uniform highp vec4 JitterOffset;
uniform highp vec4 TemporalSettings;
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;

SAMPLER2DARRAY_AUTOREG(s_ShadowCascades);
SAMPLER2DARRAY_AUTOREG(s_PreviousLightingBuffer);
IMAGE2D_ARRAY_WR_AUTOREG(s_CurrentLightingBuffer, rgba16f);

#include "./lib/common.glsl"
#include "./lib/atmosphere.glsl"
#include "./lib/froxel_util.glsl"

float calcFPShadow(vec3 worldPos){
    vec3 projPos = mul(PlayerShadowProj, vec4(worldPos, 1.0)).xyz;
    projPos.z = min(projPos.z, 1.0);
#if BGFX_SHADER_LANGUAGE_GLSL
    vec2 uvShadow = projPos.xy * 0.5 + 0.5;
    float occluder = projPos.z * 0.5 + 0.5;
#else
    vec2 uvShadow = vec2(projPos.x, -projPos.y) * 0.5 + 0.5;
    float occluder = projPos.z;
#endif
    float shadowScale = FirstPersonPlayerShadowsEnabledAndResolutionAndFilterWidthAndTextureDimensions.y;
    uvShadow = uvShadow * shadowScale + vec2(0.0, 1.0 - shadowScale);
    if (!(uvShadow.x >= 0.0 && uvShadow.x < shadowScale && uvShadow.y >= (1.0 - shadowScale) && uvShadow.y < 1.0)) return 1.0;
    float cascade = dot(CascadesPerSet, vec4_splat(1.0)) + 1.0;
    return step(occluder, texture2DArrayLod(s_ShadowCascades, vec3(uvShadow, cascade), 0.0).r);
}

int getCascade(vec3 worldPos, out vec3 projPos) {
    int numShadow = 0;
    int numCascade = int(dot(clamp(CascadesPerSet, 0.0, 1.0), vec4_splat(1.0)));
    LOOP
    for(int i = 0; i < numCascade; i++){
        int cascadePerSet = min(int(CascadesPerSet[i]), 8 - numShadow);
        LOOP
        for(int j = 0; j < cascadePerSet; j++){
            int cascadeIdx = numShadow + j;
            projPos = mul(CascadesShadowProj[cascadeIdx], vec4(worldPos, 1.0)).xyz;
            if (all(lessThanEqual(abs(projPos), vec3_splat(1.0)))) return cascadeIdx;
        }
        numShadow += cascadePerSet;
    }
    return -1;
}

float calcMainShadow(vec3 worldPos){
    vec3 projPos;
    int cascade = getCascade(worldPos, projPos);
    if (cascade < 0) return 1.0;
#if BGFX_SHADER_LANGUAGE_GLSL
    vec2 uvShadow = projPos.xy * 0.5 + 0.5;
    float occluder = projPos.z * 0.5 + 0.5;
#else
    vec2 uvShadow = vec2(projPos.x, -projPos.y) * 0.5 + 0.5;
    float occluder = projPos.z;
#endif
    float shadowScale = CascadesParameters[cascade].x;
    uvShadow = uvShadow * shadowScale + vec2(0.0, 1.0 - shadowScale);
    return step(occluder, texture2DArrayLod(s_ShadowCascades, vec3(uvShadow, cascade), 0.0).r);
}

float calcShadowMap(vec3 worldPos){
    float shadowMap = calcMainShadow(worldPos);
    float fpShadow = calcFPShadow(worldPos);
    shadowMap = min(shadowMap, fpShadow);
    return shadowMap;
}

#if THREAD_LIMIT__LIMITED_AT128
NUM_THREADS(8, 8, 2)
#elif THREAD_LIMIT__LIMITED_AT256
NUM_THREADS(8, 8, 4)
#else
NUM_THREADS(8, 8, 8)
#endif
void main() {
    ivec3 xyz = ivec3(gl_GlobalInvocationID.xyz);
    if (any(greaterThanEqual(xyz, ivec3(VolumeDimensions.xyz)))) return;

    vec3 uvw = (vec3(xyz) + JitterOffset.xyz + 0.5) / VolumeDimensions.xyz;
    vec3 worldPos = volumeToWorld(uvw);
    vec3 worldDir = normalize(worldPos);
    vec3 viewPos = mul(u_view, vec4(worldPos, 1.0)).xyz;
    float viewDist = length(viewPos);

    vec3 absorbColor = GetLightTransmittance(SunDir.xyz) * SUN_MAX_ILLUMINANCE;
    absorbColor += GetLightTransmittance(MoonDir.xyz) * MOON_MAX_ILLUMINANCE;

    float shadowMap = calcShadowMap(worldPos);

    float cosTheta = dot(worldDir, DirectionalLightSourceWorldSpaceDirection.xyz);
    float sunFade = smoothstep(0.0, 0.2, DirectionalLightSourceWorldSpaceDirection.y);
    vec3 extraMie = absorbColor * PhaseM(cosTheta, 0.7) * shadowMap * sunFade;

    vec4 transmittance;
    vec3 scattering = GetAtmosphere(vec3(0.0, 100.0, 0.0), worldDir, viewDist, SunDir.xyz, vec3_splat(1.0), transmittance, shadowMap) * SUN_MAX_ILLUMINANCE;
    scattering += GetAtmosphere(vec3(0.0, 100.0, 0.0), worldDir, viewDist, MoonDir.xyz, vec3_splat(1.0), transmittance, shadowMap) * MOON_MAX_ILLUMINANCE;

    float altitudeMod = clamp(HeightFogScaleBias.x * worldPos.y + HeightFogScaleBias.y, 0.0, 1.0);
    float fogBlend = calculateFogIntensityFaded(viewDist, FogAndDistanceControl.z, FogAndDistanceControl.x, FogAndDistanceControl.y, RenderChunkFogAlpha.x);

    vec4 scatterExt = vec4(scattering + extraMie * 5e-4, mix(1.0, 0.0, luminance(transmittance.rgb))) * saturate(1.0 - fogBlend) * altitudeMod;

    if (CameraUnderwaterAndWaterSurfaceBiasAndFalloff.r != 0.0) scatterExt = vec4_splat(0.0);

    if (TemporalSettings.x != 0.0) {
        vec3 uvwNoJitt = (vec3(xyz) + 0.5) / VolumeDimensions.xyz;
        vec3 worldPosNoJitt = volumeToWorld(uvwNoJitt);
        vec3 prevWorldPos = worldPosNoJitt - u_prevWorldPosOffset.xyz;
        vec3 prevUvw = worldToVolume(prevWorldPos);
        vec4 prevValue = sampleVolume(s_PreviousLightingBuffer, prevUvw);
        vec3 prevTexel = VolumeDimensions.xyz * prevUvw;
        vec3 prevTexelClamped = clamp(prevTexel, vec3_splat(0.0), VolumeDimensions.xyz);
        float distBoundary = distance(prevTexelClamped, prevTexel);
        float rejectH = clamp(distBoundary * TemporalSettings.y, 0.0, 1.0);
        float blendW = mix(TemporalSettings.z, 0.0, rejectH);
        imageStore(s_CurrentLightingBuffer, xyz, mix(scatterExt, prevValue, blendW));
    } else {
        imageStore(s_CurrentLightingBuffer, xyz, scatterExt);
    }
}
#endif
