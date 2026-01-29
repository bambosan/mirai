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

#if CAUSTICS_MULTIPLIER_PASS
void main() {
    gl_FragData[0] = vec4(0.0, 0.0, 0.0, 1.0);
}
#endif

#if DIRECTIONAL_LIGHTING_PASS
uniform highp vec4 DirectionalLightSourceWorldSpaceDirection;
uniform highp vec4 Time;
uniform highp vec4 WorldOrigin;

SAMPLER2D_HIGHP_AUTOREG(s_ColorMetalnessSubsurface);
SAMPLER2D_HIGHP_AUTOREG(s_Normal);
SAMPLER2D_HIGHP_AUTOREG(s_EmissiveAmbientLinearRoughness);
SAMPLER2D_HIGHP_AUTOREG(s_SceneDepth);
SAMPLER2D_HIGHP_AUTOREG(s_CausticsMultiplier);

#include "./lib/common.glsl"
#include "./lib/materials.glsl"
#include "./lib/shadow.glsl"
#include "./lib/bsdf.glsl"
#include "./lib/water_wave.glsl"

vec3 projToWorld(vec3 projPos) {
    vec4 worldPos = mul(u_invViewProj, vec4(projPos, 1.0));
    return worldPos.xyz / worldPos.w;
}

void main() {
    gl_FragData[0] = vec4_splat(0.0);

    float waterBodyMask = 1.0 - texture2D(s_CausticsMultiplier, v_texcoord0).r;
    gl_FragData[1] = vec4(waterBodyMask, 0.0, 0.0, 1.0);

    float depth = sampleDepth(s_SceneDepth, v_texcoord0);

    if (depth != 1.0) {
        vec4 data0 = texture2D(s_ColorMetalnessSubsurface, v_texcoord0);
        vec4 data1 = texture2D(s_EmissiveAmbientLinearRoughness, v_texcoord0);

        float metalness = unpackMetalness(data0.a);
        float subsurface = unpackSubsurface(data0.a);
        vec3 albedo = pow(data0.rgb, vec3_splat(2.2));
        vec3 f0 = mix(vec3_splat(0.02), albedo, metalness);
        vec3 normal = octToNdirSnorm(texture2D(s_Normal, v_texcoord0).rg);

        vec3 worldPos = projToWorld(vec3(v_projPos, depth));
        vec3 worldDir = normalize(worldPos);
        vec2 shadowMap = calcShadowMap(worldPos, normal);

        if (waterBodyMask > 0.0) {
            vec3 waterPos = worldPos - WorldOrigin.xyz;
            float caustic = calcCaustic(waterPos, DirectionalLightSourceWorldSpaceDirection.xyz, Time.x);
            shadowMap = shadowMap * (1.0 + caustic);
        }

        vec3 bsdf = BSDF(normal, DirectionalLightSourceWorldSpaceDirection.xyz, -worldDir, f0, albedo, shadowMap, metalness, data1.a, subsurface);
        gl_FragData[0].rgb = v_absorbColor * bsdf;
    }
}
#endif

#if DISCRETE_INDIRECT_COMBINED_LIGHTING_PASS
uniform highp vec4 CameraLightIntensity;

SAMPLER2D_HIGHP_AUTOREG(s_ColorMetalnessSubsurface);
SAMPLER2D_HIGHP_AUTOREG(s_EmissiveAmbientLinearRoughness);

#include "./lib/common.glsl"
#include "./lib/materials.glsl"

void main() {
    vec4 data = texture2D(s_ColorMetalnessSubsurface, v_texcoord0);
    vec3 albedo = pow(data.rgb, vec3_splat(2.2));
    float metalness = unpackMetalness(data.a);
    vec2 lightmap = texture2D(s_EmissiveAmbientLinearRoughness, v_texcoord0).gb;

    vec3 blockAmbient = BLOCK_LIGHT_COLOR * uv1x2lig(lightmap.r) * BLOCK_LIGHT_INTENSITY;
    vec3 skyAmbient = mix(pow(lightmap.g, 3.0), pow(lightmap.g, 5.0), CameraLightIntensity.y) * v_scatterColor * SKY_LIGHT_INTENSITY;
    vec3 outColor = albedo * (1.0 - metalness) * max(blockAmbient + skyAmbient, vec3_splat(MIN_AMBIENT_LIGHT));

    gl_FragData[0] = vec4(outColor, 1.0);
    gl_FragData[1] = vec4_splat(0.0);
    gl_FragData[2] = vec4_splat(0.0);
}
#endif

#if SURFACE_RADIANCE_UPSCALE_PASS
uniform highp vec4 CameraIsUnderwater;
uniform highp vec4 DimensionID;
uniform highp vec4 FogColor;
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 Time;
uniform highp vec4 FogAndDistanceControl;
uniform highp vec4 RenderChunkFogAlpha;

SAMPLER2D_HIGHP_AUTOREG(s_SceneDepth);
SAMPLER2D_HIGHP_AUTOREG(s_DiffuseLighting);
SAMPLER2D_HIGHP_AUTOREG(s_SpecularLighting);
SAMPLER2D_HIGHP_AUTOREG(s_ColorMetalnessSubsurface);
SAMPLER2D_HIGHP_AUTOREG(s_EmissiveAmbientLinearRoughness);
SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);
SAMPLER2DARRAY_AUTOREG(s_ScatteringBuffer);

#include "./lib/common.glsl"
#include "./lib/materials.glsl"
#include "./lib/atmosphere.glsl"
#include "./lib/froxel_util.glsl"

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

    vec3 outColor = vec3_splat(0.0);

    bool isTerrain = depth != 1.0;
    if (isTerrain) {
        vec3 albedo = pow(texture2D(s_ColorMetalnessSubsurface, v_texcoord0).rgb, vec3_splat(2.2));
        outColor = texture2D(s_DiffuseLighting, v_texcoord0).rgb;
        outColor += albedo * texture2D(s_EmissiveAmbientLinearRoughness, v_texcoord0).r * EMISSIVE_MATERIAL_INTENSITY;
    }

    if (DimensionID.r == 0.0) {
        vec4 transmittance;
        vec3 scattering = GetAtmosphere(vec3(0.0, 100.0, 0.0), worldDir, 1e10, SunDir.xyz, vec3_splat(1.0), transmittance) * SUN_MAX_ILLUMINANCE;
        scattering += GetAtmosphere(vec3(0.0, 100.0, 0.0), worldDir, 1e10, MoonDir.xyz, vec3_splat(1.0)) * MOON_MAX_ILLUMINANCE;

        float fogBlend = calculateFogIntensityVanilla(worldDist, FogAndDistanceControl.z, 0.92, 1.0);
        outColor = mix(outColor, scattering, fogBlend);

        if (!isTerrain) {
            outColor = calcClouds(worldDir, SunDir.xyz, MoonDir.xyz, v_scatterColor, v_absorbColor, outColor, Time.x);
            float celestialBodies = GetDisc(worldDir, SunDir.xyz, SUN_DISC_SIZE);
            celestialBodies += GetDisc(worldDir, MoonDir.xyz, MOON_DISC_SIZE);
            outColor += celestialBodies * v_absorbColor * 50.0 * transmittance.w;
        }

        if (CameraIsUnderwater.r != 0.0 && texture2D(s_SpecularLighting, v_texcoord0).r != 0.0) {
            outColor *= exp(-WATER_EXTINCTION_COEFFICIENTS * worldDist);
        }

        if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.x != 0.0) {
            vec3 uvw = ndcToVolume(projPos);
            vec4 volumetricFog = sampleVolume(s_ScatteringBuffer, uvw);
            outColor = outColor * volumetricFog.a + volumetricFog.rgb;
        }
    } else {
        float fogBlend = calculateFogIntensityFaded(worldDist, FogAndDistanceControl.z, FogAndDistanceControl.x, FogAndDistanceControl.y, RenderChunkFogAlpha.x);
        outColor = mix(outColor, pow(FogColor.rgb, vec3_splat(2.2)), fogBlend);
    }

    outColor = preExposeLighting(outColor, texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r);

    gl_FragColor = vec4(outColor, 1.0);
}
#endif

#endif //BGFX_SHADER_TYPE_FRAGMENT
