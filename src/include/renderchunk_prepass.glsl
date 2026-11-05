#include "lib/taau_utils.glsl"
#include "lib/gbuffer_utils.glsl"
#include "lib/bgfx_uniforms.glsl"

///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
uniform vec4 SubPixelOffset;

#if TRANSPILE_TARGET__MSL
in float a_texcoord4;
#else
in int a_texcoord4;
#endif
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

#if GEOMETRY_PREPASS_PASS || GEOMETRY_PREPASS_ALPHA_TEST_PASS
layout(location = 0) flat out int v_pbrTextureId;
layout(location = 1) out vec4 v_color0;
layout(location = 2) out vec3 v_tangent;
layout(location = 3) out vec3 v_bitangent;
layout(location = 4) out vec3 v_normal;
layout(location = 5) out vec3 v_worldPos;
layout(location = 6) out vec3 v_lightColor;
layout(location = 7) out vec2 v_lightmapUV;
#if SEASONS__OFF
layout(location = 8) out vec2 v_ditheringAndMaskTinting;
#endif
#endif
#if GEOMETRY_PREPASS_PASS || GEOMETRY_PREPASS_ALPHA_TEST_PASS || DEPTH_ONLY_ALPHA_TEST_PASS
layout(location = 9) out vec2 v_texcoord0;
#endif

void main() {
#if INSTANCING__ON
    vec3 worldPos = (instanceMatrix(i_data1, i_data2, i_data3) * vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = (u_model[0] * vec4(a_position, 1.0)).xyz;
#endif

#if GEOMETRY_PREPASS_PASS || GEOMETRY_PREPASS_ALPHA_TEST_PASS || DEPTH_ONLY_ALPHA_TEST_PASS
    v_texcoord0 = unpackTexcoord0(a_texcoord0);
#endif

#if GEOMETRY_PREPASS_PASS || GEOMETRY_PREPASS_ALPHA_TEST_PASS
#if RENDER_AS_BILLBOARDS__ON
    vec4 color = vec4(1.0);
    worldPos = applyBillboard(worldPos + 0.5, a_color0.rgb);
#else
    vec4 color = a_color0;
#endif

    float lightScale = a_normal.w * 0.5 + 0.5;
    Texcoord1Data data = unpackTexcoord1(a_texcoord1);
#if SEASONS__OFF
    v_ditheringAndMaskTinting = data.ditheringAndMaskTinting;
#endif
    v_lightColor = data.lightData * lightScale * 6.0;
    v_lightmapUV = data.lightmapUV;
    v_pbrTextureId = int(a_texcoord4) & 0xFFFF;
    v_worldPos = worldPos;
    v_color0 = color;
    v_normal = (u_model[0] * vec4(a_normal.xyz, 0.0)).xyz;
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
SAMPLER2D(s_MatTexture);

#if DEPTH_ONLY_ALPHA_TEST_PASS
layout(location = 9) in vec2 v_texcoord0;
out vec4 fragColor;
void main() {
    if (texture(s_MatTexture, v_texcoord0).a < 0.5) discard;
    fragColor = vec4(0.0);
}
#endif //DEPTH_ONLY_ALPHA_TEST_PASS

#if DEPTH_ONLY_OPAQUE_PASS
out vec4 fragColor;
void main() {
    fragColor = vec4(1.0);
}
#endif //DEPTH_ONLY_OPAQUE_PASS

#if GEOMETRY_PREPASS_PASS || GEOMETRY_PREPASS_ALPHA_TEST_PASS
uniform vec4 SunColor;
uniform vec4 WorldOrigin;
uniform vec4 Time;

SAMPLER2D(s_SeasonsTexture);
SAMPLER2D(s_RippleTexture);

#include "lib/common.glsl"
#include "lib/puddle.glsl"
#include "lib/materials.glsl"

layout(location = 0) flat in int v_pbrTextureId;
layout(location = 1) in vec4 v_color0;
layout(location = 2) in vec3 v_tangent;
layout(location = 3) in vec3 v_bitangent;
layout(location = 4) in vec3 v_normal;
layout(location = 5) in vec3 v_worldPos;
layout(location = 6) in vec3 v_lightColor;
layout(location = 7) in vec2 v_lightmapUV;
layout(location = 9) in vec2 v_texcoord0;
#if SEASONS__OFF
layout(location = 8) in vec2 v_ditheringAndMaskTinting;
#endif

layout(location = 0) out uvec4 fragData0;
layout(location = 1) out vec4 fragData1;
layout(location = 2) out vec4 fragData2;

void main() {
    vec3 fNormal = gl_FrontFacing ? -v_normal : v_normal;
    fNormal = normalize(fNormal);

    vec3 normal = fNormal;
    vec4 mers = vec4(0.0, 0.0, 1.0, 0.0);
    texturePBRMaterials(s_MatTexture, v_pbrTextureId, v_texcoord0, v_tangent, v_bitangent,
        normal, mers);

    if (fNormal.y > 0.0) {
        vec2 position = v_worldPos.xz - WorldOrigin.xz;

        float puddle = smoothstep(0.7, 1.0, v_lightmapUV.y)
            * smoothstep(0.45, 0.6, snoise(position * 0.05)) * max(1.0 - SunColor.r, 0.0);
        mers.b *= max(1.0 - puddle, 0.0);

        float rippleF = mod(floor(Time.r * 60.0), 64.0);

        vec2 r0 = rippleFetch(s_RippleTexture, position * 0.3, rippleF);
        vec2 r1 = rippleFetch(s_RippleTexture,
            mat2(0.8, 0.6, -0.6, 0.8) * position * 0.4 + vec2(0.37, 0.21),
            mod(rippleF + 32.0, 64.0));
        normal = mix(normal, normalize(vec3((r0 + r1) * 0.25, 1.0)).xzy, puddle);
    }

    vec4 albedo = texture(s_MatTexture, v_texcoord0);
#if GEOMETRY_PREPASS_ALPHA_TEST_PASS
    if (albedo.a < 0.5) discard;
#endif

#if SEASONS__ON
    float vanillaAO = v_color0.a;
    albedo.rgb *= mix(vec3(1.0), texture(s_SeasonsTexture, v_color0.rg).rgb * 2.0, v_color0.b);
    albedo.rgb *= 0.5;
#else
    float vanillaAO = colorAvg(v_color0.rgb);
    if (v_ditheringAndMaskTinting.y > 0.0) {
        // this block is unverified
        albedo.rgb = mix(albedo.rgb, albedo.rgb * v_color0.rgb, albedo.a);
        albedo.rgb *= 0.5;
        vanillaAO  = v_color0.a;
    } else {
        vec3 nColor = normalize(v_color0.rgb);
        float nColorAvg = colorAvg(nColor);
        if (any(notEqual(nColor.ggb, nColor.brr))) {
            albedo.rgb *= nColor;
            vanillaAO /= nColorAvg;
        }
        albedo.rgb *= min(0.5, nColorAvg);
    }
#endif

    uvec2 packedLight = packLight(swLightColor(v_lightColor, v_lightmapUV.r));

    fragData0 = uvec4(pack2x8(mers.bg), packedLight, pack2x8(vec2(vanillaAO, v_lightmapUV.y)));
    fragData1 = vec4(albedo.rgb, packMetalnessSubsurface(mers.r, mers.a));
    fragData2.xy = ndirToOctSnorm(normal);
    fragData2.zw = calculateMotionVector(
        v_worldPos,
        v_worldPos - u_prevWorldPosOffset.xyz,
        u_viewProj,
        u_prevViewProj
    );
}
#endif
#endif //SHADER_STAGE__FRAGMENT
