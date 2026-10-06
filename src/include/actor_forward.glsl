#include "lib/actor_utils.glsl"
#include "lib/taau_utils.glsl"
#include "lib/gbuffer_utils.glsl"

#if defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR)
    #if FORWARD_PBR_OPAQUE_PASS
        #define HAS_COMMON_IO 1
    #else
        #define HAS_COMMON_IO 0
    #endif
#else
    #if FORWARD_PBR_ALPHA_TEST_PASS || FORWARD_PBR_OPAQUE_PASS || FORWARD_PBR_TRANSPARENT_PASS
        #define HAS_COMMON_IO 1
    #else
        #define HAS_COMMON_IO 0
    #endif
#endif

#if defined(MATERIAL_ACTOR_BANNER_FORWARD_PBR) && HAS_COMMON_IO
    #define HAS_BANNER_TEXCOORDS 1
#else
    #define HAS_BANNER_TEXCOORDS 0
#endif

#if (defined(MATERIAL_ACTOR_GLINT_FORWARD_PBR) \
    || defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)) && HAS_COMMON_IO
    #define HAS_LAYER_UV 1
#else
    #define HAS_LAYER_UV 0
#endif

#if DEPTH_ONLY_ALPHA_TEST_PASS \
    || (HAS_COMMON_IO && !defined(MATERIAL_ACTOR_BANNER_FORWARD_PBR))
    #define HAS_TEXCOORD0 1
#else
    #define HAS_TEXCOORD0 0
#endif

#if HAS_COMMON_IO && (!defined(MATERIAL_ACTOR_BANNER_FORWARD_PBR) || TINTING__ENABLED)
    #define HAS_COLOR0 1
#else
    #define HAS_COLOR0 0
#endif

///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
uniform mat4 u_viewProj;
uniform mat4 u_view;
uniform mat4 u_proj;
uniform mat4 u_model[BGFX_CONFIG_MAX_BONES];
uniform mat4 Bones[8];
uniform vec4 SubPixelOffset;
uniform vec4 UVAnimation;
uniform vec4 SunDir;
uniform vec4 MoonDir;
uniform vec4 SunColor;
uniform vec4 BannerColors[7];
uniform vec4 BannerUVOffsetsAndScales[7];
uniform vec4 UVScale;

#include "lib/atmosphere.glsl"

#if TRANSPILE_TARGET__MSL
in float a_indices;
#else
in int a_indices;
#endif
in vec4 a_color0;
in vec4 a_normal;
in vec4 a_tangent;
in vec3 a_position;
in vec2 a_texcoord0;
#if INSTANCING__ON
in vec4 i_data1;
in vec4 i_data2;
in vec4 i_data3;
#endif

#if HAS_COMMON_IO
layout(location = 0) out vec4 v_clipPos;
layout(location = 2) out vec3 v_worldPos;
layout(location = 3) out vec3 v_tangent;
layout(location = 4) out vec3 v_bitangent;
layout(location = 5) out vec3 v_normal;
layout(location = 6) flat out vec3 v_scatterColor;
layout(location = 7) flat out vec3 v_absorbColor;
#endif
#if HAS_COLOR0
layout(location = 1) out vec4 v_color0;
#endif
#if HAS_BANNER_TEXCOORDS
layout(location = 8) centroid out vec4 v_texcoords;
#endif
#if HAS_LAYER_UV
layout(location = 8) out vec4 v_layerUV;
#endif
#if HAS_TEXCOORD0
layout(location = 9) centroid out vec2 v_texcoord0;
#endif

void main() {
    mat4 model = u_model[0] * Bones[int(a_indices)];
#if INSTANCING__ON
    vec3 worldPos = (instanceMatrix(i_data1, i_data2, i_data3) * vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = (model * vec4(a_position, 1.0)).xyz;
#endif

#if HAS_TEXCOORD0
    v_texcoord0 = applyUvAnimation(a_texcoord0, UVAnimation);
#endif
#if HAS_COMMON_IO
#if HAS_COLOR0
    v_color0 = a_color0;
#endif
    v_worldPos = worldPos;
    v_clipPos = u_viewProj * vec4(worldPos, 1.0);
    v_normal = (model * vec4(a_normal.xyz, 0.0)).xyz;
    v_tangent = (model * vec4(a_tangent.xyz, 0.0)).xyz;
    v_bitangent = (model * vec4(cross(a_normal.xyz, a_tangent.xyz) * a_tangent.w, 0.0)).xyz;
#if HAS_BANNER_TEXCOORDS
    int frameIndex = int(a_color0.a * 255.0);
    v_texcoords.xy = (BannerUVOffsetsAndScales[frameIndex].zw * a_texcoord0)
        + BannerUVOffsetsAndScales[frameIndex].xy;
    v_texcoords.zw = (BannerUVOffsetsAndScales[0].zw * a_texcoord0)
        + BannerUVOffsetsAndScales[0].xy;
#if TINTING__ENABLED
    v_color0 = BannerColors[frameIndex];
    v_color0.a = frameIndex > 0 ? 0.0 : 1.0;
#endif
#endif //HAS_BANNER_TEXCOORDS
#if HAS_LAYER_UV
    v_texcoord0 = a_texcoord0;
    v_layerUV.xy = calculateLayerUV(a_texcoord0, UVAnimation.x, UVAnimation.z, UVScale.xy);
    v_layerUV.zw = calculateLayerUV(a_texcoord0, UVAnimation.y, UVAnimation.w, UVScale.xy);
#endif //HAS_LAYER_UV
    vec3 absorbColor, scatterColor;
    calcAtmLighting(SunDir.xyz, MoonDir.xyz, SunColor.r, absorbColor, scatterColor);
    v_absorbColor = absorbColor;
    v_scatterColor = scatterColor;
#endif //HAS_COMMON_IO

    gl_Position = jitterVertexPosition(SubPixelOffset, worldPos, u_view, u_proj);
}
#endif //SHADER_STAGE__VERTEX

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
uniform vec4 ActorFPEpsilon;
uniform vec4 ChangeColor;
uniform vec4 ColorBased;
uniform vec4 MatColor;
uniform vec4 MultiplicativeTintColor;
uniform vec4 OverlayColor;
uniform vec4 TintedAlphaTestEnabled;
uniform vec4 UseAlphaRewrite;
uniform vec4 HudOpacity;
uniform vec4 GlintColor;
uniform vec4 PatternCount;
uniform vec4 PatternColors[7];
uniform vec4 PatternUVOffsetsAndScales[7];
uniform vec4 DirectionalLightSourceWorldSpaceDirection;
uniform vec4 CameraLightIntensity;
uniform vec4 AmbientLightParams;
uniform vec4 CausticsParameters;
uniform vec4 FogSkyBlend;
uniform vec4 FogAndDistanceControl;
uniform vec4 RenderChunkFogAlpha;
uniform vec4 FogColor;
uniform vec4 SunColor;
uniform vec4 VolumeDimensions;
uniform vec4 VolumeNearFar;
uniform vec4 VolumeScatteringEnabledAndPointLightVolumetricsEnabled;
uniform vec4 IBLParameters;
uniform vec4 ConvolutionType;
uniform vec4 LastSpecularIBLIdx;
uniform mat4 u_invProj;
uniform vec4 SunDir;
uniform vec4 MoonDir;
uniform vec4 CameraIsUnderwater;
uniform vec4 TileLightIntensity;
uniform vec4 BlockLightColor;

SAMPLER2D(s_MatTexture);
SAMPLER2D(s_MatTexture1);
SAMPLER2D(s_PreviousFrameAverageLuminance);

#include "lib/materials.glsl"
#include "lib/forward_shading.glsl"

#if defined(MATERIAL_ACTOR_MULTI_TEXTURE_FORWARD_PBR) \
    || defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR) \
    || defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)
SAMPLER2D(s_MatTexture2);
#endif

#ifdef MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR
vec4 getPatternAlbedo(int layer, vec2 texcoord) {
    vec2 tex = (PatternUVOffsetsAndScales[layer].zw * texcoord)
        + PatternUVOffsetsAndScales[layer].xy;
    vec4 color = PatternColors[layer];
    return texture(s_MatTexture2, tex) * color;
}
#endif

#if HAS_COMMON_IO
layout(location = 0) in vec4 v_clipPos;
layout(location = 2) in vec3 v_worldPos;
layout(location = 3) in vec3 v_tangent;
layout(location = 4) in vec3 v_bitangent;
layout(location = 5) in vec3 v_normal;
layout(location = 6) flat in vec3 v_scatterColor;
layout(location = 7) flat in vec3 v_absorbColor;
#endif
#if HAS_COLOR0
layout(location = 1) in vec4 v_color0;
#endif
#if HAS_BANNER_TEXCOORDS
layout(location = 8) centroid in vec4 v_texcoords;
#endif
#if HAS_LAYER_UV
layout(location = 8) in vec4 v_layerUV;
#endif
#if HAS_TEXCOORD0
layout(location = 9) centroid in vec2 v_texcoord0;
#endif

out vec4 fragData0;

void main() {
#if DEPTH_ONLY_ALPHA_TEST_PASS
    vec4 albedo = getActorAlbedoNoColorChange(MatColor, s_MatTexture, s_MatTexture1, v_texcoord0);
    float alpha = mix(albedo.a, albedo.a * OverlayColor.a, TintedAlphaTestEnabled.x);
    if (shouldDiscard(albedo.rgb, alpha, ActorFPEpsilon.x)) discard;
    fragData0 = vec4(0.0);
#elif DEPTH_ONLY_OPAQUE_PASS
    fragData0 = vec4(1.0);
#elif defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR) \
    && (FORWARD_PBR_ALPHA_TEST_PASS || FORWARD_PBR_TRANSPARENT_PASS)
    vec3 outColor = preExposeLighting(vec3(1.0),
        texture(s_PreviousFrameAverageLuminance, vec2(0.5)).r);
    fragData0 = vec4(outColor, 1.0);
#else

    vec4 mers = vec4(0.0, 0.0, 1.0, 0.0);
#ifdef MATERIAL_ACTOR_BANNER_FORWARD_PBR
#if TINTING__ENABLED
    vec4 albedo = getBannerAlbedo(v_color0, s_MatTexture, v_texcoords.zw, v_texcoords.xy);
#else
    vec4 albedo = getBannerAlbedo(vec4(1.0), s_MatTexture, v_texcoords.zw, v_texcoords.xy);
#endif
    albedo.a *= HudOpacity.r;
    vec3 normal = gl_FrontFacing ? -v_normal : v_normal;
    normal = normalize(normal);
    texturePBRMaterials(s_MatTexture, v_texcoords.zw, v_tangent, v_bitangent,
        normal, mers);
#else
    vec3 normal = normalize(v_normal);
    texturePBRMaterials(v_texcoord0, v_tangent, v_bitangent, normal, mers);
#endif

    if (v_normal.y > 0.0)
        mers.b = mix(smoothstep(1.0, 0.6, TileLightIntensity.g), mers.b, SunColor.r);

#if defined(MATERIAL_ACTOR_MULTI_TEXTURE_FORWARD_PBR) || defined(MATERIAL_ACTOR_TINT_FORWARD_PBR)
    vec4 albedo = getActorAlbedoNoColorChange(MatColor, s_MatTexture, s_MatTexture1,
        v_texcoord0);
    albedo = applyChangeColor(albedo, ChangeColor, MultiplicativeTintColor.rgb, 0.0);
    float alpha = 0.0;
#ifdef MATERIAL_ACTOR_TINT_FORWARD_PBR
    albedo = applySecondColorTint(albedo, MultiplicativeTintColor.rgb, s_MatTexture1,
        v_texcoord0, alpha);
#else
    albedo = applyMultitextureAlbedo(albedo, ChangeColor, s_MatTexture1, s_MatTexture2, v_texcoord0,
        ActorFPEpsilon.x, alpha);
#endif
    albedo.rgb *= mix(vec3(1.0), v_color0.rgb, ColorBased.x);
    albedo.rgb = mix(albedo.rgb, OverlayColor.rgb, OverlayColor.a);
#if FORWARD_PBR_ALPHA_TEST_PASS
    if (albedo.a < 0.5 && alpha < ActorFPEpsilon.x) discard;
#endif
#endif

#if defined(MATERIAL_ACTOR_FORWARD_PBR) \
    || defined(MATERIAL_ACTOR_GLINT_FORWARD_PBR) \
    || defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR) \
    || (defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR) && FORWARD_PBR_OPAQUE_PASS)
    vec4 albedo = getActorAlbedoNoColorChange(MatColor, s_MatTexture, s_MatTexture1, v_texcoord0);
#if FORWARD_PBR_ALPHA_TEST_PASS \
    || (defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR) && FORWARD_PBR_OPAQUE_PASS)
    float alpha = albedo.a;
    alpha = mix(alpha, alpha * OverlayColor.a, TintedAlphaTestEnabled.r);
    if (shouldDiscard(albedo.rgb, alpha, ActorFPEpsilon.r)) discard;
#endif
    albedo = applyChangeColor(albedo, ChangeColor, MultiplicativeTintColor.rgb, UseAlphaRewrite.r);
    albedo.rgb *= mix(vec3(1.0), v_color0.rgb, ColorBased.r);
    albedo.rgb = mix(albedo.rgb, OverlayColor.rgb, OverlayColor.a);
#endif

#ifdef MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR
    for (int i = 0; i < int(PatternCount.x); i++) {
        vec4 pattern = getPatternAlbedo(i, v_texcoord0);
        albedo = mix(albedo, pattern, pattern.a);
    }
    albedo.a = 1.0;
#endif

#if defined(MATERIAL_ACTOR_GLINT_FORWARD_PBR) || defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR)
    albedo.rgb = applyGlint(albedo.rgb, v_layerUV, s_MatTexture1, GlintColor);
#endif
    albedo.rgb = toLinear(albedo.rgb * 0.5);

    vec3 f0 = mix(DEFAULT_F0, albedo.rgb, mers.r);

    vec3 alwaysLit = albedo.rgb * mers.g * EMISSIVE_MATERIAL_INTENSITY;
    vec3 projPos = v_clipPos.xyz / v_clipPos.w;

    vec3 outColor = applyForwardShading(
        mers,
        f0,
        vec4(albedo.rgb, 1.0),
        v_worldPos,
        projPos,
        normal,
        BlockLightColor.rgb,
        alwaysLit,
        v_scatterColor,
        v_absorbColor,
        TileLightIntensity.rg
    );

    outColor = preExposeLighting(outColor * EXPOSURE_MULTIPLIER,
        texture(s_PreviousFrameAverageLuminance, vec2(0.5)).r);

    fragData0 = vec4(outColor, albedo.a);
#endif
}
#endif //SHADER_STAGE__FRAGMENT
