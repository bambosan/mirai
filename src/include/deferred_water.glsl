#include "./lib/common.glsl"
#include "./lib/atmosphere.glsl"

#if BGFX_SHADER_TYPE_VERTEX
#if FALLBACK_PASS
void main() {
    gl_Position = vec4_splat(0.0);
}
#else

uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 DimensionID;

void main() {
    gl_Position = vec4(a_position.xy * 2.0 - 1.0, a_position.z, 1.0);
    v_texcoord0 = a_texcoord0;
    v_projPos = gl_Position.xy;

    v_absorbColor = GetLightTransmittance(SunDir.xyz) * SUN_MAX_ILLUMINANCE;
    v_absorbColor += GetLightTransmittance(MoonDir.xyz) * MOON_MAX_ILLUMINANCE;

    if (DimensionID.r != 0.0) v_absorbColor = vec3_splat(0.0);
}
#endif
#endif

#if BGFX_SHADER_TYPE_FRAGMENT
#if FALLBACK_PASS
void main() {
    gl_FragColor = vec4_splat(0.0);
}
#else

uniform highp vec4 DimensionID;
uniform highp vec4 FogColor;
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 DirectionalLightSourceWorldSpaceDirection;
uniform highp vec4 FogAndDistanceControl;
uniform highp vec4 RenderChunkFogAlpha;
uniform highp vec4 CameraIsUnderwater;

SAMPLER2D_HIGHP_AUTOREG(s_Normal);
SAMPLER2D_HIGHP_AUTOREG(s_ColorMetalnessSubsurface);
SAMPLER2D_HIGHP_AUTOREG(s_EmissiveAmbientLinearRoughness);
SAMPLER2D_HIGHP_AUTOREG(s_SceneDepth);
SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);
SAMPLER2DARRAY_AUTOREG(s_ScatteringBuffer);

#include "./lib/froxel_util.glsl"
#include "./lib/materials.glsl"
#include "./lib/shadow.glsl"
#include "./lib/bsdf.glsl"

vec3 projToWorld(vec3 projPos) {
    vec4 worldPos = mul(u_invViewProj, vec4(projPos, 1.0));
    return worldPos.xyz / worldPos.w;
}

void main() {
    float depth = sampleDepth(s_SceneDepth, v_texcoord0);
    vec3 projPos = vec3(v_projPos, depth);
    vec3 worldPos = projToWorld(projPos);
    vec3 worldDir = normalize(worldPos);

    float worldDist = length(worldPos);

    float roughness = texture2D(s_EmissiveAmbientLinearRoughness, v_texcoord0).a;
    float metalness = unpackMetalness(texture2D(s_ColorMetalnessSubsurface, v_texcoord0).a);
    vec3 f0 = mix(vec3_splat(0.02), vec3_splat(1.0), metalness);
    vec3 normal = octToNdirSnorm(texture2D(s_Normal, v_texcoord0).rg);

    float shadowMap = calcShadowMap(worldPos, normal).r;

    vec3 brdf = BRDFSpecular(normal, DirectionalLightSourceWorldSpaceDirection.xyz, -worldDir, f0, shadowMap, roughness);

    vec3 outColor = v_absorbColor * brdf;

    gl_FragColor.a = 0.2;

    if (DimensionID.r == 0.0) {
        vec3 scattering = GetAtmosphere(vec3(0.0, 100.0, 0.0), worldDir, 1e10, SunDir.xyz, vec3_splat(1.0)) * SUN_MAX_ILLUMINANCE;
        scattering += GetAtmosphere(vec3(0.0, 100.0, 0.0), worldDir, 1e10, MoonDir.xyz, vec3_splat(1.0)) * MOON_MAX_ILLUMINANCE;
        float fogBlend = calculateFogIntensityVanilla(worldDist, FogAndDistanceControl.z, 0.92, 1.0);
        outColor = mix(outColor, scattering, fogBlend);

        if (CameraIsUnderwater.r != 0.0) {
            outColor = vec3_splat(0.0);
            gl_FragColor.a = smoothstep(1.0, 0.0, dot(normal, refract(worldDir, -normal, 1.333)));
        }
    } else {
        float fogBlend = calculateFogIntensityFaded(worldDist, FogAndDistanceControl.z, FogAndDistanceControl.x, FogAndDistanceControl.y, RenderChunkFogAlpha.x);
        outColor = mix(outColor, pow(FogColor.rgb, vec3_splat(2.2)), fogBlend);
    }

    if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.x != 0.0) {
        vec3 uvw = ndcToVolume(projPos);
        vec4 volumetricFog = sampleVolume(s_ScatteringBuffer, uvw);
        outColor = outColor * volumetricFog.a + volumetricFog.rgb;
    }

    outColor = preExposeLighting(outColor, texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r);

    gl_FragColor.rgb = outColor;

}
#endif
#endif
