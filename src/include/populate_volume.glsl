#if THREAD_LIMIT__LIMITED_AT128
layout(local_size_x = 8, local_size_y = 8, local_size_z = 2) in;
#endif
#if THREAD_LIMIT__LIMITED_AT256
layout(local_size_x = 8, local_size_y = 8, local_size_z = 4) in;
#endif
#if THREAD_LIMIT__NATIVE
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
#endif

uniform vec4 CameraLightIntensity;
uniform vec4 CameraUnderwaterAndWaterSurfaceBiasAndFalloff;
uniform vec4 DirectionalLightSourceWorldSpaceDirection;
uniform vec4 FogSkyBlend;
uniform vec4 MoonDir;
uniform vec4 SunColor;
uniform vec4 SunDir;
uniform vec4 VolumeDimensions;
uniform vec4 VolumeNearFar;
uniform mat4 u_invViewProj;
uniform mat4 u_proj;

SAMPLER2D(s_ScreenSpaceWaterFrontFaceDepthAndNormal);
SAMPLER2D(s_ScreenSpaceWaterBackFaceDepthAndNormal);
IMAGE2D_ARRAY_RO(s_CascadedShadowBuffer, r32f);
IMAGE2D_ARRAY_WO(s_ScatteringBufferOut, rgba16f);

#include "lib/froxel_utils.glsl"
#include "lib/atmosphere.glsl"

void main() {
    uvec3 xyz = gl_GlobalInvocationID;
    if (any(greaterThanEqual(xyz, uvec3(VolumeDimensions.xyz)))
        || !isOverworld(FogSkyBlend.g)) return;

    vec3 uvw = (vec3(xyz) + 0.5) / VolumeDimensions.xyz;
    vec3 worldPos = volumeToWorld(VolumeNearFar.xy, uvw, u_invViewProj, u_proj);
    vec3 worldDir = normalize(worldPos);

    float occlusion = imageLoad(s_CascadedShadowBuffer, ivec3(xyz)).r;
    float cost = dot(worldDir, DirectionalLightSourceWorldSpaceDirection.xyz);

    vec3 cRayleigh, cMie, cOzone;
    atmConstant(SunColor.r, cRayleigh, cMie, cOzone);

    vec3 absorbColor = calcLightTransmittance(SunDir.xyz, cRayleigh, cMie, cOzone, 0.75)
        * SUN_RADIANCE_MULTIPLIER;
    absorbColor += calcLightTransmittance(MoonDir.xyz, cRayleigh, cMie, cOzone, 0.0)
        * MOON_RADIANCE_MULTIPLIER;
    absorbColor *= smoothstep(0.0, 0.1, DirectionalLightSourceWorldSpaceDirection.y);

    float mie = phase(cost, 0.6, 0.0) * occlusion * SunColor.r
        * smoothstep(0.75, 0.0, DirectionalLightSourceWorldSpaceDirection.y);
    vec3 airScattering = absorbColor * mie * 0.0005;

#if TRANSPILE_TARGET__GLSL
    uvec2 newCoord = xyz.xy;
#else
    uvec2 newCoord = uvec2(xyz.x, uint(VolumeDimensions.y) - xyz.y);
#endif
    vec2 ffdn = texelFetch(s_ScreenSpaceWaterFrontFaceDepthAndNormal, ivec2(newCoord), 0).rg;
    vec2 bfdn = texelFetch(s_ScreenSpaceWaterBackFaceDepthAndNormal, ivec2(newCoord), 0).rg;
    float waterBody = smoothstep(-0.5, 0.5, (
        (((uvw.z - ffdn.r) * VolumeDimensions.z) * ffdn.g)
        - CameraUnderwaterAndWaterSurfaceBiasAndFalloff.y
    ) / CameraUnderwaterAndWaterSurfaceBiasAndFalloff.z);
    if (waterBody >= 0.0 && (uvw.z - bfdn.r) >= 0.0)
        waterBody = 0.0;
    if (CameraUnderwaterAndWaterSurfaceBiasAndFalloff.x > 0.0)
        waterBody = 1.0 - waterBody;
    vec3 waterScattering = exp(-WATER_EXTINCTION_COEFFICIENTS * 10.0)
        * phase(cost, 0.65, 0.0) * occlusion * luminance(absorbColor) * 0.01;

    vec4 totalScatter = vec4(airScattering, luminance(airScattering)) * CameraLightIntensity.y;
    totalScatter = mix(totalScatter, vec4(waterScattering, 0.0), waterBody);

    imageStore(s_ScatteringBufferOut, ivec3(xyz), totalScatter);
}
