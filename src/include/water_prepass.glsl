#include "lib/bgfx_uniforms.glsl"

///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
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
uniform vec4 SunColor;

SAMPLER2D(s_RippleTexture);

#include "lib/common.glsl"
#include "lib/materials.glsl"
#include "lib/water_wave.glsl"
#include "lib/puddle.glsl"
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
    vec3 fNormal = gl_FrontFacing ? -v_normal : v_normal;
    fNormal = normalize(fNormal);
    mat3 tbn = mat3(normalize(v_tangent), normalize(v_bitangent), fNormal);

    vec2 position = v_worldPos.xz - WorldOrigin.xz;
    vec2 waterPos = position;
    vec3 worldDir = tbn * normalize(v_worldPos);

    vec2 warpDir = worldDir.xy / worldDir.z;
    waterPos += warpDir * waves2(waterPos, Time.x) * 0.1;
    waterPos += warpDir * waves2(waterPos, Time.x) * 0.1;

    float d = exp(-length(v_worldPos) * 0.025) * 0.05;
    vec3 waterNormal = calcWaterNormal(waterPos, Time.x, d);

    if (fNormal.y > 0.0) {
        float rippleF = mod(floor(Time.r * 60.0), 64.0);

        vec2 r0 = rippleFetch(s_RippleTexture, position * 0.3, rippleF);
        vec2 r1 = rippleFetch(s_RippleTexture,
            mat2(0.8, 0.6, -0.6, 0.8) * position * 0.4 + vec2(0.37, 0.21),
            mod(rippleF + 32.0, 64.0));
        vec3 rippleNormal = normalize(vec3((r0 + r1)
            * exp(-length(v_worldPos) * 0.05) * 0.25, 1.0));

        waterNormal = mix(blendRNM(waterNormal, rippleNormal), waterNormal, SunColor.r);
    }

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
