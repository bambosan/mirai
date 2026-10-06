///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
#if FALLBACK_PASS
void main() {
    gl_Position = vec4(0.0);
}
#else
uniform vec4 SunDir;
uniform vec4 MoonDir;
uniform vec4 SunColor;

#include "lib/atmosphere.glsl"

in vec3 a_position;
in vec2 a_texcoord0;

layout(location = 0) flat out vec3 v_scatterColor;
layout(location = 1) flat out vec3 v_absorbColor;
layout(location = 2) out vec2 v_texcoord0;
layout(location = 3) out vec2 v_projPos;

void main() {
    v_texcoord0 = a_texcoord0;
    v_projPos = a_position.xy * 2.0 - 1.0;
    vec3 absorbColor, scatterColor;
    calcAtmLighting(SunDir.xyz, MoonDir.xyz, SunColor.r, absorbColor, scatterColor);
    v_absorbColor  = absorbColor;
    v_scatterColor = scatterColor;
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
#else
uniform vec4 FogColor;
uniform vec4 DirectionalLightSourceWorldSpaceDirection;
uniform vec4 FogAndDistanceControl;
uniform vec4 RenderChunkFogAlpha;
uniform vec4 CameraIsUnderwater;
uniform vec4 CameraLightIntensity;
uniform vec4 SunColor;
uniform vec4 FogSkyBlend;
uniform vec4 VolumeDimensions;
uniform vec4 VolumeNearFar;
uniform vec4 VolumeScatteringEnabledAndPointLightVolumetricsEnabled;
uniform mat4 u_invViewProj;
uniform mat4 u_invProj;

SAMPLER2D(s_Normal);
SAMPLER2D(s_SceneDepth);
SAMPLER2D(s_PreviousFrameAverageLuminance);
SAMPLER2DARRAY(s_ScatteringBuffer);

#include "lib/materials.glsl"
#include "lib/shadow.glsl"
#include "lib/brdf.glsl"
#include "lib/froxel_utils.glsl"
#include "lib/space_transf.glsl"

layout(location = 0) flat in vec3 v_scatterColor;
layout(location = 1) flat in vec3 v_absorbColor;
layout(location = 2) in vec2 v_texcoord0;
layout(location = 3) in vec2 v_projPos;

out vec4 fragColor;

void main() {
    float depth = sampleDepth(s_SceneDepth, v_texcoord0);

    vec3 projPos = vec3(v_projPos, depth);
    vec3 worldPos = projToWorld(projPos, u_invViewProj);
    vec3 worldDir = normalize(worldPos);
    float worldDist = length(worldPos);
    float wDistNorm = worldDist / FogAndDistanceControl.z;

    vec3 normal = octToNdirSnorm(texture(s_Normal, v_texcoord0).rg);

    vec2 shadowMap = calcShadowMap(worldPos, normal);

    vec3 specular = calcSpecular(normal,
        DirectionalLightSourceWorldSpaceDirection.xyz, -worldDir, WATER_F0, 0.0);

    vec3 outColor = v_absorbColor * specular * shadowMap.r * SunColor.r;

    fragColor.a = 0.2;

    if (isOverworld(FogSkyBlend.g)) {
        float fogModulator = luminance(v_absorbColor) * CameraLightIntensity.y;

        if (CameraIsUnderwater.r > 0.0) {
            outColor = exp(-WATER_EXTINCTION_COEFFICIENTS * 10.0) * fogModulator * 0.01;
            fragColor.a = smoothstep(1.0, 0.0, dot(normal, refract(worldDir, -normal, 1.333))
                * exp(-length(worldPos) * 0.15));
        } else {
            float fogFactor = clamp(wDistNorm, 0.0, 1.0);
            outColor = mix(outColor, v_scatterColor * fogModulator * PI,
                fogFactor * fogFactor * BORDER_FOG_INTENSITY);
            fragColor.a = fogFactor * fogFactor * BORDER_FOG_INTENSITY;
        }

        if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.x > 0.0) {
            vec3 uvw = ndcToVolume(VolumeNearFar.xy, projPos, u_invProj);
            vec4 volumetricFog = sampleVolume(s_ScatteringBuffer, uvw, VolumeDimensions.z);
            outColor = outColor * volumetricFog.a + volumetricFog.rgb;
            if (!(CameraIsUnderwater.r > 0.0))
                fragColor.a = max(fragColor.a, 1.0 - volumetricFog.a);
        }
    } else {
        float fogFactor = clamp((wDistNorm + RenderChunkFogAlpha.x - FogAndDistanceControl.x)
            * FogAndDistanceControl.y, 0.0, 1.0);
        vec3 linFogColor = toLinear(FogColor.rgb) * (1.0 / EXPOSURE_MULTIPLIER);
        outColor = mix(outColor, linFogColor, fogFactor);
    }

    outColor = preExposeLighting(outColor * EXPOSURE_MULTIPLIER,
        texture(s_PreviousFrameAverageLuminance, vec2(0.5)).r);

    fragColor.rgb = outColor;
}
#endif //WATER_SURFACE_PASS
#endif //SHADER_STAGE__FRAGMENT
