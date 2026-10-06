#include "lib/taau_utils.glsl"
#include "lib/actor_utils.glsl"
#include "lib/gbuffer_utils.glsl"

///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
uniform mat4 u_viewProj;
uniform mat4 u_view;
uniform mat4 u_proj;
uniform mat4 u_model[BGFX_CONFIG_MAX_BONES];
uniform mat4 PrevWorld;
uniform vec4 SubPixelOffset;
uniform vec4 UVAnimation;
uniform vec4 UVScale;

#if TRANSPILE_TARGET__MSL
in float a_texcoord4;
#else
in int a_texcoord4;
#endif
in vec4 a_color0;
in vec4 a_texcoord8;
in vec4 a_normal;
in vec4 a_tangent;
in vec3 a_position;
in vec2 a_texcoord0;
#if INSTANCING__ON
in vec4 i_data1;
in vec4 i_data2;
in vec4 i_data3;
#endif

#if !DEPTH_ONLY_ALPHA_TEST_PASS && !DEPTH_ONLY_OPAQUE_PASS
layout(location = 0) out vec4 v_color0;
layout(location = 1) out vec3 v_normal;
layout(location = 2) out vec3 v_prevWorldPos;
layout(location = 3) out vec3 v_worldPos;
#ifdef MATERIAL_ITEM_IN_HAND_PREPASS_TEXTURED
layout(location = 4) flat out int v_pbrTextureId;
layout(location = 5) out vec3 v_tangent;
layout(location = 6) out vec3 v_bitangent;
layout(location = 7) out vec2 v_texcoord0;
#else
layout(location = 4) out vec4 v_mers;
#endif
#ifdef MATERIAL_ITEM_IN_HAND_PREPASS_GLINT
layout(location = 5) out vec4 v_glintUV;
#endif
#endif

void main() {
#if INSTANCING__ON
    vec3 worldPos = (instanceMatrix(i_data1, i_data2, i_data3) * vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = (u_model[0] * vec4(a_position, 1.0)).xyz;
#endif

#if !DEPTH_ONLY_ALPHA_TEST_PASS && !DEPTH_ONLY_OPAQUE_PASS
#ifdef MATERIAL_ITEM_IN_HAND_PREPASS_TEXTURED
    v_texcoord0 = unpackTexcoord0(a_texcoord0);
    v_pbrTextureId = int(a_texcoord4);
    v_tangent = (u_model[0] * vec4(a_tangent.xyz, 0.0)).xyz;
    v_bitangent = (u_model[0] * vec4(cross(a_normal.xyz, a_tangent.xyz) * a_tangent.w, 0.0)).xyz;
#else
    v_mers = a_texcoord8;
#endif
    v_color0 = a_color0;
    v_worldPos = worldPos;
    v_normal = (u_model[0] * vec4(a_normal.xyz, 0.0)).xyz;
    v_prevWorldPos = (PrevWorld * vec4(a_position, 1.0)).xyz;
#ifdef MATERIAL_ITEM_IN_HAND_PREPASS_GLINT
    v_glintUV.xy = calculateLayerUV(a_texcoord0, UVAnimation.x, UVAnimation.z, UVScale.xy);
    v_glintUV.zw = calculateLayerUV(a_texcoord0, UVAnimation.y, UVAnimation.w, UVScale.xy);
#endif
#endif

    gl_Position = jitterVertexPosition(SubPixelOffset, worldPos, u_view, u_proj);
}
#endif //SHADER_STAGE__VERTEX

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
#if DEPTH_ONLY_ALPHA_TEST_PASS || DEPTH_ONLY_OPAQUE_PASS
out vec4 fragColor;
void main() {
    fragColor = vec4(0.0);
}
#else
uniform vec4 ChangeColor;
uniform vec4 ColorBased;
uniform vec4 GlintColor;
uniform vec4 OverlayColor;
uniform vec4 MatColor;
uniform vec4 MultiplicativeTintColor;
uniform vec4 BlockLightColor;
uniform vec4 TileLightIntensity;
uniform vec4 SunColor;
uniform vec4 u_prevWorldPosOffset;
uniform mat4 u_viewProj;
uniform mat4 u_prevViewProj;

#ifdef MATERIAL_ITEM_IN_HAND_PREPASS_TEXTURED
SAMPLER2D(s_MatTexture);
#endif
#ifdef MATERIAL_ITEM_IN_HAND_PREPASS_GLINT
SAMPLER2D(s_GlintTexture);
#endif

#include "lib/common.glsl"
#include "lib/materials.glsl"

layout(location = 0) in vec4 v_color0;
layout(location = 1) in vec3 v_normal;
layout(location = 2) in vec3 v_prevWorldPos;
layout(location = 3) in vec3 v_worldPos;
#ifdef MATERIAL_ITEM_IN_HAND_PREPASS_TEXTURED
layout(location = 4) flat in int v_pbrTextureId;
layout(location = 5) in vec3 v_tangent;
layout(location = 6) in vec3 v_bitangent;
layout(location = 7) in vec2 v_texcoord0;
#else
layout(location = 4) in vec4 v_mers;
#endif
#ifdef MATERIAL_ITEM_IN_HAND_PREPASS_GLINT
layout(location = 5) in vec4 v_glintUV;
#endif

layout(location = 0) out uvec4 fragData0;
layout(location = 1) out vec4 fragData1;
layout(location = 2) out vec4 fragData2;

void main() {
#ifdef MATERIAL_ITEM_IN_HAND_PREPASS_TEXTURED
    vec4 mers = vec4(0.0, 0.0, 1.0, 0.0);
    vec3 normal = gl_FrontFacing ? -v_normal : v_normal;
    normal = normalize(normal);
    texturePBRMaterials(s_MatTexture, v_pbrTextureId, v_texcoord0, v_tangent, v_bitangent,
        normal, mers);
    vec4 albedo = texture(s_MatTexture, v_texcoord0) * MatColor;
    albedo.rgb *= mix(vec3(1.0), v_color0.rgb, ColorBased.x);
#if MULTI_COLOR_TINT__OFF
    albedo.rgb  = mix(albedo.rgb, ChangeColor.rgb * albedo.rgb, albedo.a);
#endif
#if GEOMETRY_PREPASS_ALPHA_TEST_PASS
    if (albedo.a < 0.5) discard;
#endif
#else
    vec4 mers = v_mers;
    vec3 normal = normalize(v_normal);
    vec4 albedo = mix(vec4(1.0), vec4(v_color0.rgb, 1.0), ColorBased.x);
#if MULTI_COLOR_TINT__OFF
    albedo.rgb *= ChangeColor.rgb;
#endif
#endif //MATERIAL_ITEM_IN_HAND_PREPASS_TEXTURED
    mers.b *= SunColor.r;

#if MULTI_COLOR_TINT__ON
    albedo.rgb = applyMultiColorChange(albedo.rgb, ChangeColor.rgb,
        MultiplicativeTintColor.rgb);
#endif
    albedo.rgb = mix(albedo.rgb, OverlayColor.rgb, OverlayColor.a);
#ifdef MATERIAL_ITEM_IN_HAND_PREPASS_GLINT
    albedo.rgb = applyGlint(albedo.rgb, v_glintUV, s_GlintTexture, GlintColor);
#endif

    uvec2 packedLight = packLight(swLightColor(BlockLightColor.rgb, TileLightIntensity.r));

    fragData0 = uvec4(pack2x8(mers.bg), packedLight, pack2x8(vec2(1.0, TileLightIntensity.y)));
    fragData1 = vec4(albedo.rgb * 0.5, packMetalnessSubsurface(mers.r, mers.a));
    fragData2.xy = ndirToOctSnorm(normal);
    fragData2.zw = calculateMotionVector(
        v_worldPos,
        v_prevWorldPos - u_prevWorldPosOffset.xyz,
        u_viewProj,
        u_prevViewProj
    );
}
#endif
#endif //SHADER_STAGE__FRAGMENT
