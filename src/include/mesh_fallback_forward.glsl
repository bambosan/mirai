#include "./lib/common.glsl"
#include "./lib/atmosphere.glsl"

#if BGFX_SHADER_TYPE_VERTEX
#include "./lib/taau_util.glsl"

uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 DimensionID;

void main() {
#if INSTANCING__ON
    vec3 worldPos = mul(mtxFromCols(i_data1, i_data2, i_data3, vec4(0.0, 0.0, 0.0, 1.0)), vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = mul(u_model[0], vec4(a_position, 1.0)).xyz;
#endif
#if defined(MATERIAL_MESH_FALLBACK_MOVING_BLOCK_FORWARD_PBR) && (FORWARD_PBR_TRANSPARENT_PASS || OPAQUE_PASS)
    gl_Position = jitterVertexPosition(worldPos);
    v_pbrTextureId = a_texcoord4 & 0xffff;
    v_normal = mul(u_model[0], vec4(a_normal.xyz, 0.0)).xyz;
    v_tangent = mul(u_model[0], vec4(a_tangent.xyz, 0.0)).xyz;
    v_bitangent = mul(u_model[0], vec4(cross(a_normal.xyz, a_tangent.xyz) * a_tangent.w, 0.0)).xyz;
#else
    gl_Position = mul(u_modelViewProj, vec4(worldPos, 1.0));
#endif

    v_clipPos = mul(u_modelViewProj, vec4(worldPos, 1.0));
    v_worldPos = worldPos;
    v_color0 = a_color0;
    v_texcoord0 = a_texcoord0;

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
#if !DEPTH_ONLY_PASS && !DEPTH_ONLY_OPAQUE_PASS && !OPAQUE_PASS
uniform highp vec4 CameraLightIntensity;
uniform highp vec4 DirectionalLightSourceWorldSpaceDirection;
uniform highp vec4 TileLightIntensity;
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 CameraIsUnderwater;
uniform highp vec4 CausticsParameters;

SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);
SAMPLER2DARRAY_AUTOREG(s_ScatteringBuffer);

#include "./lib/shadow.glsl"
#include "./lib/bsdf.glsl"
#include "./lib/ibl.glsl"
#include "./lib/froxel_util.glsl"
#endif

#ifdef MATERIAL_MESH_FALLBACK_MOVING_BLOCK_FORWARD_PBR
SAMPLER2D_HIGHP_AUTOREG(s_MatTexture);
SAMPLER2D_HIGHP_AUTOREG(s_SeasonsTexture);

#include "./lib/materials.glsl"

void main() {
#if DEPTH_ONLY_PASS
    if (texture2D(s_MatTexture, v_texcoord0).a < 0.5) discard;
    gl_FragColor = vec4_splat(0.0);
#elif DEPTH_ONLY_OPAQUE_PASS
    gl_FragColor = vec4_splat(1.0);
#elif OPAQUE_PASS
    gl_FragData[0] = vec4_splat(1.0);
#else
    vec4 albedo = texture2D(s_MatTexture, v_texcoord0);

#if SEASONS__ON
    albedo.rgb *= mix(vec3_splat(1.0), texture2D(s_SeasonsTexture, v_color0.rg).rgb * 2.0, v_color0.b);
    albedo.rgb *= v_color0.a;
    albedo.a = 1.0;
#else
    albedo.rgb *= v_color0.rgb;
#endif

    albedo.rgb = pow(albedo.rgb, vec3_splat(2.2));

    vec3 normal = gl_FrontFacing ? -v_normal : v_normal;
    normal = normalize(normal);
    vec4 mers = vec4(0.0, 0.0, 1.0, 0.0);
    getTexturePBRMaterials(s_MatTexture, v_pbrTextureId, v_texcoord0, v_tangent, v_bitangent, normal, mers);

    vec3 f0 = mix(vec3_splat(0.02), albedo.rgb, mers.r);

    vec3 blockAmbient = BLOCK_LIGHT_COLOR * uv1x2lig(TileLightIntensity.r) * BLOCK_LIGHT_INTENSITY;
    vec3 skyAmbient = mix(pow(TileLightIntensity.g, 3.0), pow(TileLightIntensity.g, 5.0), CameraLightIntensity.g) * v_scatterColor;
    vec3 outColor = albedo.rgb * (1.0 - mers.r) * max(blockAmbient + skyAmbient, vec3_splat(MIN_AMBIENT_LIGHT));
    vec2 shadowMap = calcShadowMap(v_worldPos, normal);
    vec3 worldDir = normalize(v_worldPos);
    vec3 bsdf = BSDF(normal, DirectionalLightSourceWorldSpaceDirection.xyz, -worldDir, f0, albedo.rgb, shadowMap, mers.r, mers.b, mers.a);

    outColor += bsdf * v_absorbColor;
    outColor += albedo.rgb * mers.g * EMISSIVE_MATERIAL_INTENSITY;

    bool isCameraInsideWater = CameraIsUnderwater.r != 0.0 && CausticsParameters.a != 0.0;
    outColor += indirectSpecular(f0, worldDir, normal, v_scatterColor, v_absorbColor, mers.b, mers.r, TileLightIntensity.rg, !isCameraInsideWater);

    if (isCameraInsideWater) outColor *= exp(-WATER_EXTINCTION_COEFFICIENTS * length(v_worldPos));

    if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.x != 0.0) {
        vec3 projPos = v_clipPos.xyz / v_clipPos.w;
        vec3 uvw = ndcToVolume(projPos);
        vec4 volumetricFog = sampleVolume(s_ScatteringBuffer, uvw);
        outColor = outColor * volumetricFog.a + volumetricFog.rgb;
    }

    outColor = preExposeLighting(outColor, texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r);

    gl_FragData[0] = vec4(outColor, albedo.a);
#endif
}

#else //!MATERIAL_MESH_FALLBACK_MOVING_BLOCK_FORWARD_PBR

uniform highp vec4 CurrentColor;
uniform highp vec4 MERSUniforms;

#if USE_TEXTURES__ON
SAMPLER2D_HIGHP_AUTOREG(s_MatTexture);
#endif

void main() {
#if USE_TEXTURES__OFF
    vec4 albedo = vec4_splat(1.0);
#else
    vec4 albedo = texture2D(s_MatTexture, v_texcoord0);
    if (albedo.a < 0.5) discard;
#endif
    albedo *= CurrentColor;
    albedo *= v_color0;
    albedo.rgb = pow(albedo.rgb, vec3_splat(2.2));

    vec3 blockAmbient = BLOCK_LIGHT_COLOR * uv1x2lig(TileLightIntensity.r) * BLOCK_LIGHT_INTENSITY;
    vec3 skyAmbient = mix(pow(TileLightIntensity.g, 3.0), pow(TileLightIntensity.g, 5.0), CameraLightIntensity.g) * v_scatterColor * SKY_LIGHT_INTENSITY;
    vec3 outColor = albedo.rgb * (1.0 - MERSUniforms.r) * max(blockAmbient + skyAmbient, vec3_splat(MIN_AMBIENT_LIGHT));
    vec3 normal = vec3(0.0, 0.0, 1.0);
    vec3 f0 = mix(vec3_splat(0.02), albedo.rgb, MERSUniforms.r);
    vec2 shadowMap = calcShadowMap(v_worldPos, normal);
    vec3 worldDir = normalize(v_worldPos);
    vec3 bsdf = BSDF(normal, DirectionalLightSourceWorldSpaceDirection.xyz, -worldDir, f0, albedo.rgb, shadowMap, MERSUniforms.r, MERSUniforms.b, MERSUniforms.a);

    outColor += bsdf * v_absorbColor;
    outColor += albedo.rgb * MERSUniforms.g * EMISSIVE_MATERIAL_INTENSITY;

    bool isCameraInsideWater = CameraIsUnderwater.r != 0.0 && CausticsParameters.a != 0.0;
    outColor += indirectSpecular(f0, worldDir, normal, v_scatterColor, v_absorbColor, MERSUniforms.b, MERSUniforms.r, TileLightIntensity.rg, !isCameraInsideWater);

    if (isCameraInsideWater) outColor *= exp(-WATER_EXTINCTION_COEFFICIENTS * length(v_worldPos));

    if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.x != 0.0) {
        vec3 projPos = v_clipPos.xyz / v_clipPos.w;
        vec3 uvw = ndcToVolume(projPos);
        vec4 volumetricFog = sampleVolume(s_ScatteringBuffer, uvw);
        outColor = outColor * volumetricFog.a + volumetricFog.rgb;
    }

    outColor = preExposeLighting(outColor, texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r);

    gl_FragData[0] = vec4(outColor, albedo.a);
    gl_FragData[1] = vec4_splat(0.0);
    gl_FragData[2] = vec4_splat(0.0);
}
#endif //MATERIAL_MESH_FALLBACK_MOVING_BLOCK_FORWARD_PBR
#endif //BGFX_SHADER_TYPE_FRAGMENT
