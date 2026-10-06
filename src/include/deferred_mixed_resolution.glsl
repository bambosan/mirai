///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
#if FALLBACK_PASS
void main() {
    gl_Position = vec4(0.0);
}
#elif CAUSTICS_MULTIPLIER_PASS
in vec3 a_position;
void main() {
    gl_Position = vec4(a_position.xy * 2.0 - 1.0, a_position.z, 1.0);
}
#else
uniform vec4 SunDir;
uniform vec4 MoonDir;
uniform vec4 SunColor;

#include "lib/atmosphere.glsl"

in vec3 a_position;
in vec2 a_texcoord0;

layout(location = 0) out vec2 v_texcoord0;
#if !DIRECTIONAL_LIGHTING_PASS
layout(location = 1) flat out vec3 v_scatterColor;
#endif
#if !DISCRETE_INDIRECT_COMBINED_LIGHTING_PASS
layout(location = 2) flat out vec3 v_absorbColor;
layout(location = 3) out vec2 v_projPos;
#endif

void main() {
    v_texcoord0 = a_texcoord0;
    vec3 absorbColor, scatterColor;
    calcAtmLighting(SunDir.xyz, MoonDir.xyz, SunColor.r, absorbColor, scatterColor);
#if !DISCRETE_INDIRECT_COMBINED_LIGHTING_PASS
    v_absorbColor = absorbColor;
    v_projPos = a_position.xy * 2.0 - 1.0;
#endif
#if !DIRECTIONAL_LIGHTING_PASS
    v_scatterColor = scatterColor;
#endif
    gl_Position = vec4(a_position.xy * 2.0 - 1.0, a_position.z, 1.0);
}
#endif
#endif //SHADER_STAGE__VERTEX

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
#if FALLBACK_PASS
out vec4 fragColor;
void main() {
    fragColor = vec4(0.0);
}
#endif //FALLBACK_PASS

#if CAUSTICS_MULTIPLIER_PASS
out vec4 fragData0;
void main() {
    fragData0 = vec4(0.0, 1.0, 1.0, 1.0);
}
#endif //CAUSTICS_MULTIPLIER_PASS

#if DIRECTIONAL_LIGHTING_PASS
uniform vec4 DirectionalLightSourceWorldSpaceDirection;
uniform vec4 Time;
uniform vec4 WorldOrigin;
uniform vec4 FogAndDistanceControl;
uniform vec4 SunColor;
uniform mat4 u_invViewProj;

SAMPLER2D(s_ColorMetalnessSubsurface);
SAMPLER2D(s_Normal);
SAMPLER2D(s_SceneDepth);
SAMPLER2D(s_CausticsMultiplier);
USAMPLER2D(s_EmissiveAmbientLinearRoughness);

#include "lib/materials.glsl"
#include "lib/space_transf.glsl"
#include "lib/shadow.glsl"
#include "lib/brdf.glsl"
#include "lib/water_wave.glsl"

layout(location = 2) flat in vec3 v_absorbColor;
layout(location = 3) in vec2 v_projPos;
layout(location = 0) in vec2 v_texcoord0;

layout(location = 0) out vec4 fragData0;
layout(location = 1) out vec4 fragData1;

void main() {
    float depth = sampleDepth(s_SceneDepth, v_texcoord0);

    vec3 worldPos = projToWorld(vec3(v_projPos, depth), u_invViewProj);
    vec3 worldDir = normalize(worldPos);
    vec3 position = worldPos - WorldOrigin.xyz;

    uvec4 data16 = texelFetch(s_EmissiveAmbientLinearRoughness,
        ivec2(gl_FragCoord.xy), 0) & 0xFFFFu;
    float roughness = float(data16.r >> 8) * (1.0 / 255.0);
    float emissive = float(data16.r & 0xFFu) * (1.0 / 255.0);

    vec4 data = texture(s_ColorMetalnessSubsurface, v_texcoord0);
    vec3 albedo = toLinear(data.rgb);
    float metalness = unpackMetalness(data.a);
    float subsurface = unpackSubsurface(data.a);
    vec3 f0 = mix(DEFAULT_F0, albedo, metalness);

    vec3 normal = octToNdirSnorm(texture(s_Normal, v_texcoord0).rg);

    vec2 shadowMap = calcShadowMap(worldPos, normal);

    float waterBodyMask = texture(s_CausticsMultiplier, v_texcoord0).r;

    if (waterBodyMask < 1.0) {
        float caustic = calcCaustic(position, DirectionalLightSourceWorldSpaceDirection.xyz,
            Time.x) * PI;
        shadowMap = (FogAndDistanceControl.r < EPSILON)
            ? shadowMap * (caustic + 0.1)
            : shadowMap * (caustic + 1.0);
    }

    vec3 alwaysLit = albedo * emissive * EMISSIVE_MATERIAL_INTENSITY;

    vec3 specular = calcSpecular(normal,
        DirectionalLightSourceWorldSpaceDirection.xyz, -worldDir, f0, roughness);

    albedo = (1.0 - metalness) * albedo;

    float fdiffuse = diffuseLambert(normal, DirectionalLightSourceWorldSpaceDirection.xyz);
    float wdiffuse = diffuseWrap(normal, DirectionalLightSourceWorldSpaceDirection.xyz, 0.5);
    vec3 diffuse = mix(fdiffuse, wdiffuse, subsurface) * albedo;
    vec3 tDiffuse = diffuseWrap(-normal,
        DirectionalLightSourceWorldSpaceDirection.xyz, 0.5) * subsurface * albedo;

    fragData0 = depth < 1.0
        ? vec4(v_absorbColor
            * (diffuse * shadowMap.r + tDiffuse * shadowMap.g + specular * shadowMap.r)
            * SunColor.r + alwaysLit, 1.0)
        : vec4(0.0);
    fragData1 = vec4(waterBodyMask, 0.0, 0.0, 1.0);
}
#endif //DIRECTIONAL_LIGHTING_PASS

#if DISCRETE_INDIRECT_COMBINED_LIGHTING_PASS
uniform vec4 CameraLightIntensity;
uniform vec4 AmbientLightParams;
uniform vec4 DirectionalLightSourceWorldSpaceDirection;

SAMPLER2D(s_ColorMetalnessSubsurface);
USAMPLER2D(s_EmissiveAmbientLinearRoughness);

#include "lib/common.glsl"
#include "lib/materials.glsl"

layout(location = 1) flat in vec3 v_scatterColor;
layout(location = 0) in vec2 v_texcoord0;

layout(location = 0) out vec4 fragData0;
layout(location = 1) out vec4 fragData1;
layout(location = 2) out vec4 fragData2;

void main() {
    uvec4 data16 = texelFetch(s_EmissiveAmbientLinearRoughness,
        ivec2(gl_FragCoord.xy), 0) & 0xFFFFu;

    vec4 blightColor = vec4(data16.g >> 8, data16.g & 0xFFu,
        data16.b >> 8, data16.b & 0xFFu) * (1.0 / 255.0);
    float skyLightmap = float(data16.a & 0xFFu) * (1.0 / 255.0);
    float vanillaAO = float(data16.a >> 8) * (1.0 / 255.0);

    vec4 data = texture(s_ColorMetalnessSubsurface, v_texcoord0);

    vec3 albedo = toLinear(data.rgb);
    float metalness = unpackMetalness(data.a);
    albedo = (1.0 - metalness) * albedo;

    vec3 blmColor = blightColor.rgb * blightColor.a * 6.0;
    vec3 blockAmbient = (blmColor + blmColor * blmColor * blmColor * blmColor * 10.0)
        * BLOCK_AMBIENT_MULTIPLIER;

    float skylmContrib = mix(pow(skyLightmap, 3.0), pow(skyLightmap, 5.0),
        CameraLightIntensity.y);
    vec3 skyAmbient = saturation(v_scatterColor, 0.5)
        * PI * skylmContrib * SKY_AMBIENT_MULTIPLIER;

    vec3 ambientLight = max(
        blockAmbient * vanillaAO + skyAmbient * vanillaAO * vanillaAO,
        vec3(AmbientLightParams.a * vanillaAO * vanillaAO * (1.0 / EXPOSURE_MULTIPLIER))
    );

    fragData0 = vec4(0.0);
    fragData1 = vec4(albedo * ambientLight, 1.0);
    fragData2 = vec4(0.0);
}
#endif //DISCRETE_INDIRECT_COMBINED_LIGHTING_PASS

#if SURFACE_RADIANCE_UPSCALE_PASS
uniform vec4 CameraLightIntensity;
uniform vec4 FogColor;
uniform vec4 SunDir;
uniform vec4 MoonDir;
uniform vec4 DirectionalLightSourceWorldSpaceDirection;
uniform vec4 Time;
uniform vec4 FogAndDistanceControl;
uniform vec4 RenderChunkFogAlpha;
uniform vec4 WorldOrigin;
uniform vec4 SunColor;
uniform vec4 FogSkyBlend;
uniform vec4 VolumeDimensions;
uniform vec4 VolumeNearFar;
uniform vec4 VolumeScatteringEnabledAndPointLightVolumetricsEnabled;
uniform mat4 u_invViewProj;
uniform mat4 u_invProj;

SAMPLER2D(s_SceneDepth);
SAMPLER2D(s_DiffuseLighting);
SAMPLER2D(s_SpecularLighting);
SAMPLER2D(s_PreviousFrameAverageLuminance);
SAMPLER2DARRAY(s_ScatteringBuffer);

#include "lib/materials.glsl"
#include "lib/atmosphere.glsl"
#include "lib/froxel_utils.glsl"
#include "lib/clouds.glsl"
#include "lib/space_transf.glsl"

layout(location = 2) flat in vec3 v_absorbColor;
layout(location = 1) flat in vec3 v_scatterColor;
layout(location = 3) in vec2 v_projPos;
layout(location = 0) in vec2 v_texcoord0;

out vec4 fragData0;

void main() {
    float depth = sampleDepth(s_SceneDepth, v_texcoord0);

    vec3 projPos = vec3(v_projPos, depth);
    vec3 worldPos = projToWorld(projPos, u_invViewProj);
    vec3 worldDir = normalize(worldPos);
    float worldDist = length(worldPos);
    float wDistNorm = worldDist / FogAndDistanceControl.z;

    vec3 outColor = vec3(0.0);

    bool isTerrain = depth < 1.0;
    if (isTerrain) outColor = texture(s_DiffuseLighting, v_texcoord0).rgb;

    if (isOverworld(FogSkyBlend.g)) {
        bool isWater = texture(s_SpecularLighting, v_texcoord0).r < 1.0
            && FogAndDistanceControl.r < EPSILON;

        float fogModulator = luminance(v_absorbColor) * CameraLightIntensity.y;

        if (isTerrain) {
            float fogFactor = isWater ? 0.0 : clamp(wDistNorm, 0.0, 1.0);
            outColor = mix(outColor, v_scatterColor * fogModulator * PI,
                fogFactor * fogFactor * BORDER_FOG_INTENSITY);
        } else {
            outColor = calcAtmSky(worldDir, SunDir.xyz, MoonDir.xyz, SunColor.r);
        }

        vec3 cloudColor = SunDir.y > 0.0 ? v_absorbColor : v_absorbColor * SunColor.r * 0.5;
        applyCirrusClouds(outColor, worldDir, -WorldOrigin.xyz,
            DirectionalLightSourceWorldSpaceDirection.xyz, cloudColor, Time.x, isTerrain);

        if (isWater) {
            outColor *= exp(-WATER_EXTINCTION_COEFFICIENTS * worldDist);
            outColor = mix(outColor, exp(-WATER_EXTINCTION_COEFFICIENTS * 10.0)
                * fogModulator, 0.01);
        }

        if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.x > 0.0) {
            vec3 uvw = ndcToVolume(VolumeNearFar.xy, projPos, u_invProj);
            vec4 volumetricFog = sampleVolume(s_ScatteringBuffer, uvw, VolumeDimensions.z);
            outColor = outColor * volumetricFog.a + volumetricFog.rgb;
        }
    } else {
        float fogFactor = clamp((wDistNorm + RenderChunkFogAlpha.x - FogAndDistanceControl.x)
            * FogAndDistanceControl.y, 0.0, 1.0);
        vec3 linFogColor = toLinear(FogColor.rgb) * (1.0 / EXPOSURE_MULTIPLIER);
        outColor = mix(outColor, linFogColor, fogFactor);
    }

    outColor = preExposeLighting(outColor * EXPOSURE_MULTIPLIER,
        texture(s_PreviousFrameAverageLuminance, vec2(0.5)).r);

    fragData0 = vec4(outColor, 1.0);
}
#endif //SURFACE_RADIANCE_UPSCALE_PASS
#endif //SHADER_STAGE__FRAGMENT
