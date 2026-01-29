#include "./lib/common.glsl"
#include "./lib/actor_util.glsl"
#include "./lib/taau_util.glsl"
#include "./lib/atmosphere.glsl"

#if BGFX_SHADER_TYPE_VERTEX
uniform vec4 UVAnimation;
uniform mat4 Bones[8];
uniform vec4 SunDir;
uniform vec4 MoonDir;
uniform vec4 DimensionID;

#ifdef MATERIAL_ACTOR_BANNER_FORWARD_PBR
uniform vec4 BannerColors[7];
uniform vec4 BannerUVOffsetsAndScales[7];
#endif

#if defined(MATERIAL_ACTOR_GLINT_FORWARD_PBR) || defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)
uniform vec4 UVScale;
#endif

void main() {
    mat4 model = mul(u_model[0], Bones[int(a_indices)]);
#if INSTANCING__ON
    vec3 worldPos = mul(mtxFromCols(i_data1, i_data2, i_data3, vec4(0.0, 0.0, 0.0, 1.0)), vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = mul(model, vec4(a_position, 1.0)).xyz;
#endif

    gl_Position = jitterVertexPosition(worldPos);

    v_texcoord0 = applyUvAnimation(a_texcoord0, UVAnimation);

#if !DEPTH_ONLY_PASS && !DEPTH_ONLY_OPAQUE_PASS
    v_color0 = a_color0;
    v_worldPos = worldPos;
    v_clipPos = mul(u_modelViewProj, vec4(worldPos, 1.0));

    v_normal = mul(model, vec4(a_normal.xyz, 0.0)).xyz;
    v_tangent = mul(model, vec4(a_tangent.xyz, 0.0)).xyz;
    v_bitangent = mul(model, vec4(cross(a_normal.xyz, a_tangent.xyz) * a_tangent.w, 0.0)).xyz;

#ifdef MATERIAL_ACTOR_BANNER_FORWARD_PBR
    int frameIndex = int(a_color0.a * 255.0);
    v_texcoords.xy = (BannerUVOffsetsAndScales[frameIndex].zw * a_texcoord0) + BannerUVOffsetsAndScales[frameIndex].xy;
    v_texcoords.zw = (BannerUVOffsetsAndScales[0].zw * a_texcoord0) + BannerUVOffsetsAndScales[0].xy;
#if TINTING__ENABLED
    v_color0 = BannerColors[frameIndex];
    v_color0.a = frameIndex > 0 ? 0.0 : 1.0;
#endif
#endif //MATERIAL_ACTOR_BANNER_FORWARD_PBR

#if defined(MATERIAL_ACTOR_GLINT_FORWARD_PBR) || defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)
    v_texcoord0 = a_texcoord0;
    v_layerUV.xy = calculateLayerUV(a_texcoord0, UVAnimation.x, UVAnimation.z, UVScale.xy);
    v_layerUV.zw = calculateLayerUV(a_texcoord0, UVAnimation.y, UVAnimation.w, UVScale.xy);
#endif

    v_absorbColor = GetLightTransmittance(SunDir.xyz) * SUN_MAX_ILLUMINANCE;
    v_absorbColor += GetLightTransmittance(MoonDir.xyz) * MOON_MAX_ILLUMINANCE;
    v_scatterColor = GetAtmosphere(vec3(0.0, 100.0, 0.0), vec3(0.0, 1.0, 0.0), 1e10, SunDir.xyz, vec3_splat(1.0)) * SUN_MAX_ILLUMINANCE;
    v_scatterColor += GetAtmosphere(vec3(0.0, 100.0, 0.0), vec3(0.0, 1.0, 0.0), 1e10, MoonDir.xyz, vec3_splat(1.0)) * MOON_MAX_ILLUMINANCE;

    if (DimensionID.r != 0.0) {
        v_absorbColor = vec3_splat(0.0);
        v_scatterColor = vec3_splat(1.0);
    }
#endif
}

#endif //BGFX_SHADER_TYPE_VERTEX


#if BGFX_SHADER_TYPE_FRAGMENT
uniform highp vec4 ActorFPEpsilon;
uniform highp vec4 ChangeColor;
uniform highp vec4 ColorBased;
uniform highp vec4 MatColor;
uniform highp vec4 MultiplicativeTintColor;
uniform highp vec4 OverlayColor;
uniform highp vec4 TintedAlphaTestEnabled;
uniform highp vec4 UseAlphaRewrite;

#if defined(MATERIAL_ACTOR_BANNER_FORWARD_PBR) || \
defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR) || \
defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)

uniform highp vec4 HudOpacity;
#endif

#if defined(MATERIAL_ACTOR_GLINT_FORWARD_PBR) || defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)
uniform highp vec4 GlintColor;
#endif

SAMPLER2D_HIGHP_AUTOREG(s_MatTexture);
SAMPLER2D_HIGHP_AUTOREG(s_MatTexture1);

#if defined(MATERIAL_ACTOR_MULTI_TEXTURE_FORWARD_PBR) || \
defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR) || \
defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)

SAMPLER2D_HIGHP_AUTOREG(s_MatTexture2);
#endif

#ifdef MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR
uniform highp vec4 PatternCount;
uniform highp vec4 PatternColors[7];
uniform highp vec4 PatternUVOffsetsAndScales[7];

vec4 getPatternAlbedo(int layer, vec2 texcoord) {
    vec2 tex = (PatternUVOffsetsAndScales[layer].zw * texcoord) + PatternUVOffsetsAndScales[layer].xy;
    vec4 color = PatternColors[layer];
    return texture2D(s_MatTexture2, tex) * color;
}
#endif

#if !DEPTH_ONLY_PASS && !DEPTH_ONLY_OPAQUE_PASS
uniform highp vec4 DirectionalLightSourceWorldSpaceDirection;
uniform highp vec4 TileLightIntensity;
uniform highp vec4 CameraLightIntensity;
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 CameraIsUnderwater;
uniform highp vec4 CausticsParameters;

SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);
SAMPLER2DARRAY_AUTOREG(s_ScatteringBuffer);

#include "./lib/materials.glsl"
#include "./lib/shadow.glsl"
#include "./lib/bsdf.glsl"
#include "./lib/ibl.glsl"
#include "./lib/froxel_util.glsl"
#endif

void main() {
#if DEPTH_ONLY_PASS
    vec4 albedo = getActorAlbedoNoColorChange(MatColor, s_MatTexture, s_MatTexture1, v_texcoord0);
    float alpha = mix(albedo.a, albedo.a * OverlayColor.a, TintedAlphaTestEnabled.x);
    if (shouldDiscard(albedo.rgb, alpha, ActorFPEpsilon.x)) discard;
    gl_FragData[0] = vec4_splat(0.0);
#elif DEPTH_ONLY_OPAQUE_PASS
    gl_FragData[0] = vec4_splat(1.0);
#elif defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR) && (FORWARD_PBR_ALPHA_TEST_PASS || FORWARD_PBR_TRANSPARENT_PASS)
    vec3 outColor = preExposeLighting(vec3_splat(1.0), texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r);
    gl_FragData[0] = vec4(outColor, 1.0);
#else


#if defined(MATERIAL_ACTOR_MULTI_TEXTURE_FORWARD_PBR) || defined(MATERIAL_ACTOR_TINT_FORWARD_PBR)
    vec4 albedo = getActorAlbedoNoColorChange(MatColor, s_MatTexture, s_MatTexture1, v_texcoord0);
    albedo = applyChangeColor(albedo, ChangeColor, MultiplicativeTintColor.rgb, 0.0);

    float alpha = 0.0;
#ifdef MATERIAL_ACTOR_TINT_FORWARD_PBR
    albedo = applySecondColorTint(albedo, MultiplicativeTintColor.rgb, s_MatTexture1, v_texcoord0, alpha);
#else
    albedo = applyMultitextureAlbedo(albedo, ChangeColor, s_MatTexture1, s_MatTexture2, v_texcoord0, ActorFPEpsilon.x, alpha);
#endif
    albedo.rgb *= mix(vec3_splat(1.0), v_color0.rgb, ColorBased.x);
    albedo.rgb = mix(albedo.rgb, OverlayColor.rgb, OverlayColor.a);

#if FORWARD_PBR_ALPHA_TEST_PASS
    if (albedo.a < 0.5 && alpha < ActorFPEpsilon.x) discard;
#endif
#endif


#if (defined(MATERIAL_ACTOR_BANNER_FORWARD_PBR) && FORWARD_PBR_ALPHA_TEST_PASS) || \
    defined(MATERIAL_ACTOR_FORWARD_PBR) || \
    defined(MATERIAL_ACTOR_GLINT_FORWARD_PBR) || \
    (defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR) && FORWARD_PBR_OPAQUE_PASS) || \
    defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)

    vec4 albedo = getActorAlbedoNoColorChange(MatColor, s_MatTexture, s_MatTexture1, v_texcoord0);

#if FORWARD_PBR_ALPHA_TEST_PASS || (defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR) && FORWARD_PBR_OPAQUE_PASS)
    float alpha = albedo.a;
    alpha = mix(alpha, alpha * OverlayColor.a, TintedAlphaTestEnabled.r);
    if (shouldDiscard(albedo.rgb, alpha, ActorFPEpsilon.r)) discard;
#endif

    albedo = applyChangeColor(albedo, ChangeColor, MultiplicativeTintColor.rgb, UseAlphaRewrite.r);
    albedo.rgb *= mix(vec3_splat(1.0), v_color0.rgb, ColorBased.r);
    albedo.rgb = mix(albedo.rgb, OverlayColor.rgb, OverlayColor.a);
#endif


    vec4 mers = vec4(0.0, 0.0, 1.0, 0.0);

#if defined(MATERIAL_ACTOR_BANNER_FORWARD_PBR) && (FORWARD_PBR_OPAQUE_PASS || FORWARD_PBR_TRANSPARENT_PASS)
    vec4 albedo = getBannerAlbedo(v_color0, s_MatTexture, v_texcoords.zw, v_texcoords.xy);
    albedo.a *= HudOpacity.r;

    vec3 normal = gl_FrontFacing ? -v_normal : v_normal;
    normal = normalize(normal);
    getTexturePBRMaterials(s_MatTexture, v_texcoords.zw, v_tangent, v_bitangent, normal, mers);
#else
    vec3 normal = normalize(v_normal);
    getTexturePBRMaterials(v_texcoord0, v_tangent, v_bitangent, normal, mers);
#endif

#ifdef MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR
    LOOP
    for (int i = 0; i < int(PatternCount.x); i++) {
        vec4 pattern = getPatternAlbedo(i, v_texcoord0);
        albedo = mix(albedo, pattern, pattern.a);
    }
    albedo.a = 1.0;
#endif

#if defined(MATERIAL_ACTOR_GLINT_FORWARD_PBR) || defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)
    albedo.rgb = applyGlint(albedo.rgb, v_layerUV, s_MatTexture1, GlintColor);
#endif

    albedo.rgb = pow(albedo.rgb, vec3_splat(2.2));

    vec3 f0 = mix(vec3_splat(0.02), albedo.rgb, mers.r);

    vec3 blockAmbient = BLOCK_LIGHT_COLOR * uv1x2lig(TileLightIntensity.r) * BLOCK_LIGHT_INTENSITY;
    vec3 skyAmbient = mix(pow(TileLightIntensity.g, 3.0), pow(TileLightIntensity.g, 5.0), CameraLightIntensity.g) * v_scatterColor * SKY_LIGHT_INTENSITY;
    vec3 outColor = albedo.rgb * (1.0 - mers.r) * max(blockAmbient + skyAmbient, vec3_splat(MIN_AMBIENT_LIGHT));

    vec3 worldDir = normalize(v_worldPos);
    vec2 shadowMap = calcShadowMap(v_worldPos, normal);
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

#endif //BGFX_SHADER_TYPE_FRAGMENT
