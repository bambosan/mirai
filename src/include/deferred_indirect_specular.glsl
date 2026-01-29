#if BGFX_SHADER_TYPE_VERTEX
#if FALLBACK_PASS
void main() {
    gl_Position = vec4_splat(0.0);
}
#else
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 DimensionID;

#include "./lib/common.glsl"
#include "./lib/atmosphere.glsl"

void main() {
    gl_Position = vec4(a_position.xy * 2.0 - 1.0, a_position.z, 1.0);
    v_texcoord0 = a_texcoord0;
    v_projPos = gl_Position.xy;

    v_absorbColor = GetLightTransmittance(SunDir.xyz) * SUN_MAX_ILLUMINANCE;
    v_absorbColor += GetLightTransmittance(MoonDir.xyz) * MOON_MAX_ILLUMINANCE;
    v_scatterColor = GetAtmosphere(vec3(0.0, 100.0, 0.0), vec3(0.0, 1.0, 0.0), 1e10, SunDir.xyz, vec3_splat(1.0)) * SUN_MAX_ILLUMINANCE;
    v_scatterColor += GetAtmosphere(vec3(0.0, 100.0, 0.0), vec3(0.0, 1.0, 0.0), 1e10, MoonDir.xyz, vec3_splat(1.0)) * MOON_MAX_ILLUMINANCE;

    if (DimensionID.r != 0.0) {
        v_absorbColor = vec3_splat(0.0);
        v_scatterColor = vec3_splat(1.0);
    }
}
#endif
#endif

#if BGFX_SHADER_TYPE_FRAGMENT
#if FALLBACK_PASS
void main() {
    gl_FragColor = vec4_splat(0.0);
}
#endif

#if DO_INDIRECT_SPECULAR_SHADING_DUAL_TARGET_PASS || DO_INDIRECT_SPECULAR_SHADING_SINGLE_TARGET_PASS
uniform highp vec4 CameraIsUnderwater;
uniform highp vec4 ViewportScale;
uniform highp vec4 AmbientLightParams;
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 FogAndDistanceControl;
uniform highp vec4 RenderChunkFogAlpha;
uniform highp vec4 DimensionID;

SAMPLER2D_HIGHP_AUTOREG(s_ColorMetalnessSubsurface);
SAMPLER2D_HIGHP_AUTOREG(s_EmissiveAmbientLinearRoughness);
SAMPLER2D_HIGHP_AUTOREG(s_Normal);
SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);
SAMPLER2D_HIGHP_AUTOREG(s_SceneDepth);
SAMPLER2DARRAY_AUTOREG(s_ScatteringBuffer);

#include "./lib/common.glsl"
#include "./lib/materials.glsl"
#include "./lib/atmosphere.glsl"
#include "./lib/froxel_util.glsl"
#include "./lib/ibl.glsl"

vec3 projToWorld(vec3 projPos) {
    vec4 worldPos = mul(u_invViewProj, vec4(projPos, 1.0));
    return worldPos.xyz / worldPos.w;
}

void main() {
    float depth = sampleDepth(s_SceneDepth, v_texcoord0);
    vec3 outColor = vec3_splat(0.0);

    if (depth != 1.0) {
        vec4 data0 = texture2D(s_ColorMetalnessSubsurface, v_texcoord0);
        vec4 data1 = texture2D(s_Normal, v_texcoord0);
        vec4 data2 = texture2D(s_EmissiveAmbientLinearRoughness, v_texcoord0);

        float exposure = texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r;
        float metalness = unpackMetalness(data0.a);

        vec3 albedo = pow(data0.rgb, vec3_splat(2.2));
        vec3 f0 = mix(vec3_splat(0.02), albedo, metalness);
        vec3 normal = octToNdirSnorm(data1.rg);
        vec3 projPos = vec3(v_projPos, depth);
        vec3 worldPos = projToWorld(projPos);
        vec3 worldDir = normalize(worldPos);

        bool isCameraUnderWater = CameraIsUnderwater.r != 0.0;
        outColor = indirectSpecular(f0, worldDir, normal, v_scatterColor, v_absorbColor, v_texcoord0, data2.a, metalness, data2.gb, exposure, !isCameraUnderWater);

        float worldDist = length(worldPos);
        float fogBlend = (DimensionID.r == 0.0) ? calculateFogIntensityVanilla(worldDist, FogAndDistanceControl.z, 0.92, 1.0) : calculateFogIntensityFaded(worldDist, FogAndDistanceControl.z, FogAndDistanceControl.x, FogAndDistanceControl.y, RenderChunkFogAlpha.x);
        outColor = outColor * saturate(1.0 - fogBlend);

        if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.x != 0.0) {
            vec3 uvw = ndcToVolume(projPos);
            vec4 volumetricFog = sampleVolume(s_ScatteringBuffer, uvw);
            outColor *= volumetricFog.a;
        }

        outColor = preExposeLighting(outColor.rgb, exposure);
    }

#if DO_INDIRECT_SPECULAR_SHADING_SINGLE_TARGET_PASS
    gl_FragColor = vec4(outColor, 1.0);
#else
    gl_FragData[0] = vec4(outColor, 1.0);
    gl_FragData[1] = vec4_splat(0.0);
#endif
}
#endif

#if DO_INDIRECT_SPECULAR_UPSCALE_PASS
SAMPLER2D_HIGHP_AUTOREG(s_SpecularLighting);
SAMPLER2D_HIGHP_AUTOREG(s_SceneDepth);

void main() {
    gl_FragColor = vec4_splat(0.0);
    if (texture2D(s_SceneDepth, v_texcoord0).r != 1.0) gl_FragColor.rgb = texture2D(s_SpecularLighting, v_texcoord0).rgb;
}
#endif

#endif //BGFX_SHADER_TYPE_FRAGMENT
