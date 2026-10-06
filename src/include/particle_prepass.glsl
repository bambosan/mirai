#include "lib/taau_utils.glsl"
#include "lib/gbuffer_utils.glsl"

///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
uniform mat4 u_viewProj;
uniform mat4 u_view;
uniform mat4 u_proj;
uniform mat4 u_model[BGFX_CONFIG_MAX_BONES];
uniform vec4 SubPixelOffset;

in vec4 a_color0;
in vec4 a_normal;
in vec4 a_tangent;
in vec3 a_position;
in vec2 a_texcoord0;
in vec2 a_texcoord1;
#if INSTANCING__ON
in vec4 i_data1;
in vec4 i_data2;
in vec4 i_data3;
#endif

layout(location = 0) out vec4 v_color0;
layout(location = 1) out vec2 v_texcoord0;
#if GEOMETRY_PREPASS_ALPHA_TEST_PASS
layout(location = 2) out vec3 v_tangent;
layout(location = 3) out vec3 v_bitangent;
layout(location = 4) out vec3 v_normal;
layout(location = 5) out vec3 v_worldPos;
layout(location = 6) out vec3 v_lightColor;
layout(location = 7) out vec2 v_lightmapUV;
#endif

void main() {
#if INSTANCING__ON
    vec3 worldPos = (instanceMatrix(i_data1, i_data2, i_data3) * vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = (u_model[0] * vec4(a_position, 1.0)).xyz;
#endif

    v_color0 = a_color0;
    v_texcoord0 = a_texcoord0;
#if GEOMETRY_PREPASS_ALPHA_TEST_PASS
    uvec2 data16 = uvec2(roundEven(a_texcoord1 * 65535.0)) & 0xFFFFu;
    uint lo = data16.g & 0xFFu;
    v_lightColor = vec3(data16.r >> 8, data16.r & 0xFFu, data16.g >> 8) / 255.0;
    v_lightmapUV = vec2(uvec2(lo >> 4, lo) & 15u) / 15.0;
    v_worldPos = worldPos;
    v_normal = a_normal.xyz;
    v_tangent = (u_model[0] * vec4(a_tangent.xyz, 0.0)).xyz;
    v_bitangent = (u_model[0] * vec4(cross(a_normal.xyz, a_tangent.xyz) * a_tangent.w, 0.0)).xyz;

    gl_Position = jitterVertexPosition(SubPixelOffset, worldPos, u_view, u_proj);
#else
    gl_Position = u_viewProj * vec4(worldPos, 1.0);
#endif
}
#endif //SHADER_STAGE__VERTEX

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
SAMPLER2D(s_ParticleTexture);

layout(location = 0) in vec4 v_color0;
layout(location = 1) in vec2 v_texcoord0;

#if GEOMETRY_PREPASS_ALPHA_TEST_PASS
uniform vec4 MERSUniforms;
uniform vec4 PBRTextureFlags;
uniform vec4 SunColor;
uniform vec4 u_prevWorldPosOffset;
uniform mat4 u_viewProj;
uniform mat4 u_prevViewProj;

SAMPLER2D(s_MERSTexture);
SAMPLER2D(s_NormalTexture);

#include "lib/common.glsl"
#include "lib/materials.glsl"

layout(location = 2) in vec3 v_tangent;
layout(location = 3) in vec3 v_bitangent;
layout(location = 4) in vec3 v_normal;
layout(location = 5) in vec3 v_worldPos;
layout(location = 6) in vec3 v_lightColor;
layout(location = 7) in vec2 v_lightmapUV;
#endif

layout(location = 0) out uvec4 fragData0;
layout(location = 1) out vec4 fragData1;
layout(location = 2) out vec4 fragData2;

void main() {
#if ALPHA_TEST_PASS || TRANSPARENT_PASS
    vec4 albedo = texture(s_ParticleTexture, v_texcoord0);
#if ALPHA_TEST_PASS
    if (albedo.a < 0.5) discard;
    albedo.rgb *= v_color0.rgb;
    albedo.a = 1.0;
#else
    albedo *= v_color0;
#endif
    fragData0 = uvec4(0);
    fragData1 = albedo;
    fragData2 = vec4(0.0);
#else
    vec4 albedo = texture(s_ParticleTexture, v_texcoord0);
    if (albedo.a < 0.5) discard;
    albedo *= v_color0;

    int pbrTextureFlags = int(PBRTextureFlags.r);

    vec4 mers = MERSUniforms;
    if ((pbrTextureFlags & kPBRHasMaterialTexture) == kPBRHasMaterialTexture) {
        vec4 mersTex = texture(s_MERSTexture, v_texcoord0);
        mers.rgb = mersTex.rgb;
        if ((pbrTextureFlags & kPBRHasSubsurfaceChannel) == kPBRHasSubsurfaceChannel)
            mers.a = mersTex.a;
    }
    mers.b *= SunColor.r;

    vec3 normal = v_normal;
    if ((pbrTextureFlags & kPBRHasNormalTexture) == kPBRHasNormalTexture) {
        vec3 normalt = texture(s_NormalTexture, v_texcoord0).rgb * 2.0 - 1.0;
        mat3 tbn = mat3(normalize(v_tangent), normalize(v_bitangent), normal);
        normal = tbn * normalt;
    }

    uvec2 packedLight = packLight(swLightColor(v_lightColor, v_lightmapUV.r));

    fragData0 = uvec4(pack2x8(mers.bg), packedLight, pack2x8(vec2(1.0, v_lightmapUV.y)));
    fragData1 = vec4(albedo.rgb * 0.5, packMetalnessSubsurface(mers.r, mers.a));
    fragData2.xy = ndirToOctSnorm(normal);
    fragData2.zw = calculateMotionVector(
        v_worldPos,
        v_worldPos - u_prevWorldPosOffset.xyz,
        u_viewProj,
        u_prevViewProj
    );
#endif
}
#endif //SHADER_STAGE__FRAGMENT
