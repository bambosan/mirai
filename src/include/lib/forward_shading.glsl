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
    specular = mix(specular, specular * luminance(albedo.rgb), mers.b);

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
    tDiffuse *= (1.0 + shadowMap.g
        * phase(dot(DirectionalLightSourceWorldSpaceDirection.xyz, worldDir), 0.6, 0.0)
        * 2.0 * mers.a * PI);

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
    albedo.rgb *= (1.0 - mers.r);

    vec3 blmColor = swLightColor(lightColor, lightmap.r);
    vec3 ambientLight = calcAmbientLight(albedo, blmColor, scatterColor, absorbColor, lightmap);
    vec3 direcLight = calcDirectionalLight(mers, albedo, f0, worldPos, worldDir, normal,
        absorbColor);

    vec3 outColor = ambientLight + direcLight + alwaysLit;

    float worldDist = length(worldPos);
    float wDistNorm = worldDist / FogAndDistanceControl.z;

    if (isOverworld(FogSkyBlend.g)) {
        float occluder = linearstep(0.7, 1.0, lightmap.g);
        vec3 ispecular = indirectSpecular(
            IBLParameters,
            f0,
            worldDir,
            normal,
            ConvolutionType.r,
            LastSpecularIBLIdx.r,
            mers.b,
            occluder
        );
        ispecular = mix(ispecular, ispecular * luminance(albedo.rgb), mers.b);
        outColor += ispecular;

        if (CausticsParameters.a > 0.0) {
            float wFogModulator = luminance(absorbColor) * CameraLightIntensity.y;
            outColor = outColor * exp(-WATER_EXTINCTION_COEFFICIENTS * worldDist)
                + WATER_SCATTERING_COEFFICIENTS * wFogModulator * 0.01;
        } else {
            float fwDistNorm6 = worldDist / 96.0;
            float dFogModulator = CameraLightIntensity.y
                * smoothstep(0.0, 0.2, DirectionalLightSourceWorldSpaceDirection.y);

            float hFogModulator = smoothstep(1.0, 0.0, DirectionalLightSourceWorldSpaceDirection.y)
                * smoothstep(0.0, 1.0, SunDir.x)
                * CameraLightIntensity.y;

            vec3 hFogExt = fwDistNorm6 * fwDistNorm6 * hFogModulator * saturation(absorbColor, 0.5)
                * vec3(0.6, 0.8, 1.0) * HEIGHT_FOG_INTENSITY;
            vec3 hfFogExt = hFogExt * smoothstep(90.0, 0.0, -WorldOrigin.y) * 1.01;
            vec3 hFogTsm = exp(-hFogExt * linearstep(90.0, 62.0, worldPos.y - WorldOrigin.y));

            vec3 dFogExt = wDistNorm * wDistNorm * dFogModulator
                * scatterColor * DISTANT_FOG_INTENSITY;
            vec3 dFogTsm = exp(-dFogExt);

            vec3 rFogExt = fwDistNorm6 * fwDistNorm6 * scatterColor
                * CameraLightIntensity.y * RAIN_FOG_INTENSITY;

            vec3 fFogTsm = exp(-mix(rFogExt, hfFogExt, SunColor.r));

            outColor = outColor * dFogTsm + (1.0 - dFogTsm);
            outColor = outColor * hFogTsm + (1.0 - hFogTsm);
            outColor = outColor * fFogTsm + (1.0 - fFogTsm);
        }

        if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.r > 0.0) {
            vec3 uvw = ndcToVolume(VolumeNearFar.xy, projPos, u_invProj);
            vec4 volumetricFog = sampleVolume(s_ScatteringBuffer, uvw, VolumeDimensions.z);
            outColor = outColor * volumetricFog.a + volumetricFog.rgb;
        }
    } else {
        float borderFog = clamp((wDistNorm + RenderChunkFogAlpha.x
            - FogAndDistanceControl.x) * FogAndDistanceControl.y, 0.0, 1.0);
        vec3 linFogColor = toLinear(FogColor.rgb) * (1.0 / EXPOSURE_MULTIPLIER);
        outColor = mix(outColor, linFogColor, borderFog);
    }

    return outColor;
}

#endif
