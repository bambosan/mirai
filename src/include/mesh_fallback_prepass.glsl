#include "lib/gbuffer_utils.glsl"

///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
uniform mat4 u_viewProj;
uniform mat4 u_model[BGFX_CONFIG_MAX_BONES];
uniform vec4 UVAnimation;

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

#if !DEPTH_ONLY_ALPHA_TEST_PASS
layout(location = 0) out vec3 v_worldPos;
layout(location = 1) out vec3 v_normal;
layout(location = 2) out vec4 v_color0;
#if USE_TEXTURES__ON
layout(location = 3) out vec2 v_texcoord0;
#endif
#endif

void main() {
#if INSTANCING__ON
    vec3 worldPos = (instanceMatrix(i_data1, i_data2, i_data3) * vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = (u_model[0] * vec4(a_position, 1.0)).xyz;
#endif

#if !DEPTH_ONLY_ALPHA_TEST_PASS
    v_color0 = a_color0;
    v_worldPos = worldPos;
    v_normal = (u_model[0] * vec4(a_normal.xyz, 0.0)).xyz;
#if USE_TEXTURES__ON
    v_texcoord0 = UVAnimation.xy + (a_texcoord0 * UVAnimation.zw);
#endif
#endif

    gl_Position = (u_viewProj * vec4(worldPos, 1.0));
}
#endif //SHADER_STAGE__VERTEX

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
#if DEPTH_ONLY_ALPHA_TEST_PASS
out vec4 fragColor;
void main() {
    fragColor = vec4(0.0);
}
#else
uniform vec4 BlockLightColor;
uniform vec4 TileLightIntensity;
uniform vec4 CurrentColor;
uniform vec4 MERSUniforms;
uniform vec4 u_prevWorldPosOffset;
uniform mat4 u_viewProj;
uniform mat4 u_prevViewProj;

SAMPLER2D(s_MatTexture);

#include "lib/common.glsl"
#include "lib/materials.glsl"
#include "lib/taau_utils.glsl"

layout(location = 0) in vec3 v_worldPos;
layout(location = 1) in vec3 v_normal;
layout(location = 2) in vec4 v_color0;
#if USE_TEXTURES__ON
layout(location = 3) in vec2 v_texcoord0;
#endif

layout(location = 0) out uvec4 fragData0;
layout(location = 1) out vec4 fragData1;
layout(location = 2) out vec4 fragData2;

void main() {
#if USE_TEXTURES__ON
    vec4 albedo = texture(s_MatTexture, v_texcoord0);
    if (albedo.a < 0.5) discard;
#else
    vec4 albedo = vec4(1.0);
#endif
    albedo.rgb *= CurrentColor.rgb * v_color0.rgb;

    uvec2 packedLight = packLight(swLightColor(BlockLightColor.rgb, TileLightIntensity.r));

    fragData0 = uvec4(pack2x8(MERSUniforms.bg), packedLight,
        pack2x8(vec2(1.0, TileLightIntensity.y)));
    fragData1 = vec4(albedo.rgb * 0.5, packMetalnessSubsurface(MERSUniforms.r, MERSUniforms.a));
    fragData2.xy = ndirToOctSnorm(normalize(v_normal));
    fragData2.zw = calculateMotionVector(
        v_worldPos,
        v_worldPos - u_prevWorldPosOffset.xyz,
        u_viewProj,
        u_prevViewProj
    );
}
#endif
#endif //SHADER_STAGE__FRAGMENT
