#ifndef FORWARD_SHADING_INCLUDED
#define FORWARD_SHADING_INCLUDED

SAMPLER2DARRAY(s_ScatteringBuffer);

#include "shadow.glsl"
#include "clouds.glsl"
#include "brdf.glsl"
#include "ibl.glsl"
#include "froxel_utils.glsl"

vec3 calcAmbientLight(
    vec4 albedo,
    vec3 blmColor,
    vec3 scatterColor,
    vec3 absorbColor,
    vec2 lightmap
) {
    vec3 blockAmbient = (blmColor + pow(blmColor, vec3(5.0)) * 10.0)
        * BLOCK_AMBIENT_MULTIPLIER;

    float skyOcclusion = lightmap.g * lightmap.g
        * (linearstep(0.9, 1.0, lightmap.g) * 0.5 + 0.5);
    vec3 skyAmbient = saturation(scatterColor, 0.5) * skyOcclusion * SKY_AMBIENT_MULTIPLIER;

    return albedo.rgb * max(
        blockAmbient * albedo.a + skyAmbient * albedo.a * albedo.a,
        vec3(AmbientLightParams.a * albedo.a * albedo.a * (1.0 / EXPOSURE_MULTIPLIER))
    );
}

vec3 calcDirectionalLight(
    vec4 mers,
    vec4 albedo,
    vec3 f0,
    vec3 worldPos,
    vec3 worldDir,
    vec3 normal,
    vec3 absorbColor
) {
    vec3 shadowMap = calcShadowMap(worldPos, normal).rgr;

#if CUMULUS_ENABLED
    float cloudShadow = calcCloudShadow(
        worldPos - WorldOrigin.xyz,
        DirectionalLightSourceWorldSpaceDirection.xyz,
        2.0,
        Time.x,
        SunColor.r
    );
    shadowMap.rg = min(shadowMap.rg,
        vec2(cloudShadow * CUMULUS_SHADOW_CONTRIBUTION + (1.0 - CUMULUS_SHADOW_CONTRIBUTION)));
    shadowMap.b = min(shadowMap.b, cloudShadow);
#endif

    vec3 specular = calcSpecular(normal,
        DirectionalLightSourceWorldSpaceDirection.xyz, -worldDir, f0, mers.b);

    mers.a *= linearstep(
        ShadowFilterOffsetAndRangeFarAndMapSizeAndNormalOffsetStrength.y - 16.0,
        ShadowFilterOffsetAndRangeFarAndMapSizeAndNormalOffsetStrength.y - 24.0,
        length(worldPos)
    );

    float fdiffuse = diffuseLambert(normal, DirectionalLightSourceWorldSpaceDirection.xyz);
    float wdiffuse = diffuseWrap(normal, DirectionalLightSourceWorldSpaceDirection.xyz, 0.5);
    vec3 diffuse = mix(fdiffuse, wdiffuse, mers.a) * albedo.rgb;
    vec3 tDiffuse = diffuseWrap(-normal, DirectionalLightSourceWorldSpaceDirection.xyz, 0.5)
        * mers.a * albedo.rgb;

    return absorbColor * (
        diffuse * shadowMap.r + tDiffuse * shadowMap.g + specular * shadowMap.b
    ) * SunColor.r;
}

vec3 applyForwardShading(
    vec4 mers,
    vec3 f0,
    vec4 albedo,
    vec3 worldPos,
    vec3 projPos,
    vec3 normal,
    vec3 lightColor,
    vec3 alwaysLit,
    vec3 scatterColor,
    vec3 absorbColor,
    vec2 lightmap
) {
    vec3 worldDir = normalize(worldPos);
    albedo.rgb = albedo.rgb * (1.0 - mers.r);

    vec3 blmColor = swLightColor(lightColor, lightmap.r);
    vec3 ambientLight = calcAmbientLight(albedo, blmColor, scatterColor, absorbColor, lightmap);
    vec3 direcLight = calcDirectionalLight(mers, albedo, f0, worldPos, worldDir, normal,
        absorbColor);

    vec3 outColor = ambientLight + direcLight + alwaysLit;

    float worldDist = length(worldPos);

    if (isOverworld(FogSkyBlend.g)) {
        float occluder = linearstep(0.7, 1.0, lightmap.g);
        outColor += indirectSpecular(
            IBLParameters,
            f0,
            worldDir,
            normal,
            ConvolutionType.r,
            LastSpecularIBLIdx.r,
            mers.b,
            occluder
        );

        float fogModulator = luminance(absorbColor) * CameraLightIntensity.y;
        bool isWaterBody = CausticsParameters.a > 0.0;

        float fogFactor = isWaterBody
            ? 0.0 : clamp(worldDist / FogAndDistanceControl.z, 0.0, 1.0);
        outColor = mix(outColor, scatterColor * fogModulator,
            fogFactor * fogFactor * BORDER_FOG_INTENSITY);

        if (isWaterBody) {
            outColor *= exp(-WATER_EXTINCTION_COEFFICIENTS * worldDist);
            outColor = mix(outColor, WATER_SCATTERING_COEFFICIENTS * fogModulator, 0.01);
        }

        if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.r > 0.0) {
            vec3 uvw = ndcToVolume(VolumeNearFar.xy, projPos, u_invProj);
            vec4 volumetricFog = sampleVolume(s_ScatteringBuffer, uvw, VolumeDimensions.z);
            outColor = outColor * volumetricFog.a + volumetricFog.rgb;
        }
    } else {
        float wDistNorm = worldDist / FogAndDistanceControl.z;
        float borderFog = clamp((wDistNorm + RenderChunkFogAlpha.x
            - FogAndDistanceControl.x) * FogAndDistanceControl.y, 0.0, 1.0);
        vec3 linFogColor = toLinear(FogColor.rgb) * (1.0 / EXPOSURE_MULTIPLIER);
        outColor = mix(outColor, linFogColor, borderFog);
    }

    return outColor;
}

#endif
