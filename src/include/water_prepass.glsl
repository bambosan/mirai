///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
uniform mat4 u_viewProj;
uniform mat4 u_view;
uniform mat4 u_proj;
uniform mat4 u_model[BGFX_CONFIG_MAX_BONES];

#include "lib/gbuffer_utils.glsl"

in vec2 a_texcoord1;
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
layout(location = 0) out vec3 v_normal;
layout(location = 1) out vec3 v_worldPos;
#if DEPTH_AND_NORMAL_PASS
layout(location = 2) out vec4 v_clipPos;
#else
layout(location = 2) out vec3 v_tangent;
layout(location = 3) out vec3 v_bitangent;
layout(location = 4) out vec3 v_lightColor;
layout(location = 5) out vec2 v_lightmapUV;
#endif
#endif

void main() {
#if INSTANCING__ON
    vec3 worldPos = (instanceMatrix(i_data1, i_data2, i_data3) * vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = (u_model[0] * vec4(a_position, 1.0)).xyz;
#endif
    vec4 clipPos = u_viewProj * vec4(worldPos, 1.0);

#if !DEPTH_ONLY_ALPHA_TEST_PASS
    v_worldPos = worldPos;
    v_normal = (u_model[0] * vec4(a_normal.xyz, 0.0)).xyz;
#if DEPTH_AND_NORMAL_PASS
    v_clipPos = clipPos;
#else
    float lightScale = a_normal.w * 0.5 + 0.5;
    Texcoord1Data data = unpackTexcoord1(a_texcoord1);
    v_lightColor = data.lightData * lightScale * 6.0;
    v_lightmapUV = data.lightmapUV;
    v_tangent = (u_model[0] * vec4(a_tangent.xyz, 0.0)).xyz;
    v_bitangent = (u_model[0] * vec4(cross(a_normal.xyz, a_tangent.xyz) * a_tangent.w, 0.0)).xyz;
#endif
#endif

    gl_Position = clipPos;
}
#endif //SHADER_STAGE__VERTEX

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
#if DEPTH_ONLY_ALPHA_TEST_PASS
out vec4 fragColor;
void main() {
    fragColor = vec4(1.0);
}
#endif //DEPTH_ONLY_ALPHA_TEST_PASS

#if DEPTH_AND_NORMAL_PASS
#include "lib/froxel_utils.glsl"

uniform vec4 VolumeNearFar;
uniform mat4 u_invProj;

layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec3 v_worldPos;
layout(location = 2) in vec4 v_clipPos;

out vec4 fragData0;

void main() {
    vec3 projPos = v_clipPos.xyz / v_clipPos.w;
    vec3 uvw = ndcToVolume(VolumeNearFar.xy, projPos, u_invProj);
    fragData0 = vec4(uvw.z, abs(dot(v_normal, normalize(-v_worldPos))), 0.0, 1.0);
}
#endif //DEPTH_AND_NORMAL_PASS

#if DO_WATER_SURFACE_BUFFER_PASS
uniform vec4 WorldOrigin;
uniform vec4 Time;
uniform vec4 u_prevWorldPosOffset;
uniform mat4 u_viewProj;
uniform mat4 u_prevViewProj;

#include "lib/common.glsl"
#include "lib/materials.glsl"
#include "lib/water_wave.glsl"
#include "lib/taau_utils.glsl"
#include "lib/gbuffer_utils.glsl"

layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec3 v_worldPos;
layout(location = 2) in vec3 v_tangent;
layout(location = 3) in vec3 v_bitangent;
layout(location = 4) in vec3 v_lightColor;
layout(location = 5) in vec2 v_lightmapUV;

layout(location = 0) out uvec4 fragData0;
layout(location = 1) out vec4 fragData1;
layout(location = 2) out vec4 fragData2;

void main() {
    vec3 normal = gl_FrontFacing ? -v_normal : v_normal;
    normal = normalize(normal);
    mat3 tbn = mat3(normalize(v_tangent), normalize(v_bitangent), normal);

    vec2 waterPos = v_worldPos.xz - WorldOrigin.xz;
    float d = clamp(exp(-length(v_worldPos.xz) * 0.05), 0.0, 1.0) * 0.05;
    vec3 waterNormal = calcWaterNormal(waterPos, Time.x, d);
    waterNormal = tbn * waterNormal;

    uvec2 packedLight = packLight(swLightColor(v_lightColor, v_lightmapUV.r));

    fragData0 = uvec4(0u, packedLight, pack2x8(vec2(1.0, v_lightmapUV.y)));
    fragData1 = vec4(0.0);
    fragData2.xy = ndirToOctSnorm(waterNormal);
    fragData2.zw = calculateMotionVector(
        v_worldPos,
        v_worldPos - u_prevWorldPosOffset.xyz,
        u_viewProj,
        u_prevViewProj
    );
}
#endif //DO_WATER_SURFACE_BUFFER_PASS
#endif //SHADER_STAGE__FRAGMENT
