#include "./lib/common.glsl"
#include "./lib/atmosphere.glsl"

#if BGFX_SHADER_TYPE_VERTEX
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 DimensionID;

void main(){
#if INSTANCING__ON
    vec3 worldPos = mul(mtxFromCols(i_data1, i_data2, i_data3, vec4(0.0, 0.0, 0.0, 1.0)), vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = mul(u_model[0], vec4(a_position, 1.0)).xyz;
#endif
    gl_Position = mul(u_viewProj, vec4(worldPos, 1.0));
    v_clipPos = gl_Position;
    v_color0 = a_color0;
    v_worldPos = worldPos;
    v_texcoord0 = a_texcoord0;
    v_ambientLight = a_texcoord1;

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

#if BGFX_SHADER_TYPE_FRAGMENT

SAMPLER2D_HIGHP_AUTOREG(s_ParticleTexture);

#if FORWARD_PBR_TRANSPARENT_PASS
uniform highp vec4 CameraIsUnderwater;
uniform highp vec4 CameraLightIntensity;
uniform highp vec4 CausticsParameters;
uniform highp vec4 DirectionalLightSourceWorldSpaceDirection;
uniform highp vec4 MERSUniforms;
uniform highp vec4 PBRTextureFlags;
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;

SAMPLER2D_HIGHP_AUTOREG(s_MERSTexture);
SAMPLER2D_HIGHP_AUTOREG(s_NormalTexture);
SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);
SAMPLER2DARRAY_AUTOREG(s_ScatteringBuffer);

#include "./lib/materials.glsl"
#include "./lib/shadow.glsl"
#include "./lib/bsdf.glsl"
#include "./lib/ibl.glsl"
#include "./lib/froxel_util.glsl"
#endif

void main() {
    vec4 albedo = texture2D(s_ParticleTexture, v_texcoord0);
#if ALPHA_TEST_PASS
    if (albedo.a < 0.5) discard;
#endif
    albedo *= v_color0;
#if !TRANSPARENT_PASS
    albedo.a = 1.0;
#endif
#if FORWARD_PBR_TRANSPARENT_PASS
    albedo.rgb = pow(albedo.rgb, vec3_splat(2.2));

    int pbrTextureFlags = int(PBRTextureFlags.r);
    vec4 mers = MERSUniforms;
    if ((pbrTextureFlags & kPBRTextureDataFlagHasMaterialTexture) == kPBRTextureDataFlagHasMaterialTexture) {
        vec4 mersTex = texture2D(s_MERSTexture, v_texcoord0);
        mers.rgb = mersTex.rgb;
        if ((pbrTextureFlags & kPBRTextureDataFlagHasSubsurfaceChannel) == kPBRTextureDataFlagHasSubsurfaceChannel) mers.a = mersTex.a;
    }
    vec3 normal = ((pbrTextureFlags & kPBRTextureDataFlagHasNormalTexture) == kPBRTextureDataFlagHasNormalTexture) ? mul(u_model[0], vec4(texture2D(s_NormalTexture, v_texcoord0).rgb * 2.0 - 1.0, 0.0)).xyz : vec3_splat(0.0);
    vec3 f0 = mix(vec3_splat(0.02), albedo.rgb, mers.r);

    vec3 blockAmbient = BLOCK_LIGHT_COLOR * uv1x2lig(v_ambientLight.r) * BLOCK_LIGHT_INTENSITY;
    vec3 skyAmbient = mix(pow(v_ambientLight.g, 3.0), pow(v_ambientLight.g, 5.0), CameraLightIntensity.g) * v_scatterColor * SKY_LIGHT_INTENSITY;
    vec3 outColor = albedo.rgb * (1.0 - mers.r) * max(blockAmbient + skyAmbient, vec3_splat(MIN_AMBIENT_LIGHT));
    vec2 shadowMap = calcShadowMap(v_worldPos, normal);
    vec3 worldDir = normalize(v_worldPos);
    vec3 bsdf = BSDF(normal, DirectionalLightSourceWorldSpaceDirection.xyz, -worldDir, f0, albedo.rgb, shadowMap, mers.r, mers.b, mers.a, SubsurfaceScatteringContributionAndDiffuseWrapValueAndFalloffScale.g);

    outColor += bsdf * v_absorbColor;
    outColor += albedo.rgb * mers.g * EMISSIVE_MATERIAL_INTENSITY;
    outColor += indirectSpecular(f0, albedo.rgb, worldDir, normal, v_scatterColor, v_absorbColor, mers.b, mers.r, v_ambientLight);

    if (CameraIsUnderwater.r != 0.0 && CausticsParameters.a != 0.0) outColor *= exp(-WATER_EXTINCTION_COEFFICIENTS * length(v_worldPos));

    if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.x != 0.0) {
        vec3 projPos = v_clipPos.xyz / v_clipPos.w;
        vec3 uvw = ndcToVolume(projPos);
        vec4 volumetricFog = sampleVolume(s_ScatteringBuffer, uvw);
        outColor = outColor * volumetricFog.a + volumetricFog.rgb;
    }

    outColor = preExposeLighting(outColor, texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r);

    gl_FragColor = vec4(outColor, albedo.a);
#else
    gl_FragColor = albedo;
#endif
}
#endif
