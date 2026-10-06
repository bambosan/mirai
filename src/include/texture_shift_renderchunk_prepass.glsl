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
in vec2 a_texcoord1;
in vec4 a_normal;
in vec4 a_tangent;
in vec3 a_position;
in vec2 a_texcoord0;
in vec2 a_texcoord2;
#if INSTANCING__ON
in vec4 i_data1;
in vec4 i_data2;
in vec4 i_data3;
#endif

layout(location = 0) flat out vec2 v_textureShift;
layout(location = 1) out vec2 v_texcoord0;
#if GEOMETRY_PREPASS_PASS || GEOMETRY_PREPASS_ALPHA_TEST_PASS
layout(location = 2) out vec4 v_color0;
layout(location = 3) out vec3 v_tangent;
layout(location = 4) out vec3 v_bitangent;
layout(location = 5) out vec3 v_normal;
layout(location = 6) out vec3 v_worldPos;
layout(location = 7) out vec2 v_lightmapUV;
layout(location = 8) out vec3 v_lightColor;
#endif

void main() {
#if INSTANCING__ON
    vec3 worldPos = (instanceMatrix(i_data1, i_data2, i_data3) * vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = (u_model[0] * vec4(a_position, 1.0)).xyz;
#endif

    v_textureShift = a_texcoord2;
    v_texcoord0 = unpackTexcoord0(a_texcoord0);
#if GEOMETRY_PREPASS_PASS || GEOMETRY_PREPASS_ALPHA_TEST_PASS
    float lightScale = a_normal.w * 0.5 + 0.5;
    Texcoord1Data data = unpackTexcoord1(a_texcoord1);
    v_lightColor = data.lightData * lightScale * 6.0;
    v_lightmapUV = data.lightmapUV;
    v_worldPos = worldPos;
    v_color0 = a_color0;
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
uniform vec4 u_prevWorldPosOffset;
uniform mat4 u_viewProj;
uniform mat4 u_prevViewProj;

struct TextureShiftBuffer {
    float preUV0;
    float preUV1;
    float postUV0;
    float postUV1;
    int packedPBRId;
    float globalAlpha;
    float localShiftLength;
};

BUFFER_RO(s_TextureShiftBufferData, TextureShiftBuffer, s_TextureShiftBufferData1);
SAMPLER2D(s_MatTexture);

#include "lib/common.glsl"
#include "lib/materials.glsl"

layout(location = 0) flat in vec2 v_textureShift;
layout(location = 1) in vec2 v_texcoord0;

#if DEPTH_ONLY_ALPHA_TEST_PASS
out vec4 fragColor;
void main() {
    int shiftBufferIndex = int(roundEven(v_textureShift.y * 65535.0)) & 0xFFFF;
    TextureShiftBuffer textureShiftBuffer = s_TextureShiftBufferData1._data[shiftBufferIndex];
    vec4 preFrameSample  = texture(s_MatTexture,
        vec2(v_texcoord0.x + textureShiftBuffer.preUV0,
            v_texcoord0.y + textureShiftBuffer.preUV1)
    );
    vec4 postFrameSample = texture(s_MatTexture,
        vec2(v_texcoord0.x + textureShiftBuffer.postUV0,
            v_texcoord0.y + textureShiftBuffer.postUV1)
    );
    float blendFactor = clamp(
        (textureShiftBuffer.globalAlpha
            - ((1.0 - textureShiftBuffer.localShiftLength) * v_textureShift.x))
        / textureShiftBuffer.localShiftLength, 0.0, 1.0);
    vec4 albedo = mix(preFrameSample, postFrameSample, blendFactor);
    if (albedo.a < 0.5) discard;
    fragColor = vec4(0.0);
}
#endif //DEPTH_ONLY_ALPHA_TEST_PASS

#if GEOMETRY_PREPASS_PASS || GEOMETRY_PREPASS_ALPHA_TEST_PASS
layout(location = 2) in vec4 v_color0;
layout(location = 3) in vec3 v_tangent;
layout(location = 4) in vec3 v_bitangent;
layout(location = 5) in vec3 v_normal;
layout(location = 6) in vec3 v_worldPos;
layout(location = 7) in vec2 v_lightmapUV;
layout(location = 8) in vec3 v_lightColor;

layout(location = 0) out uvec4 fragData0;
layout(location = 1) out vec4 fragData1;
layout(location = 2) out vec4 fragData2;

void main() {
    int shiftBufferIndex = int(roundEven(v_textureShift.y * 65535.0)) & 0xFFFF;
    TextureShiftBuffer textureShiftBuffer = s_TextureShiftBufferData1._data[shiftBufferIndex];

    vec4 preFrameSample = texture(s_MatTexture,
        vec2(v_texcoord0.x + textureShiftBuffer.preUV0,
            v_texcoord0.y + textureShiftBuffer.preUV1)
    );
    vec4 postFrameSample = texture(s_MatTexture,
        vec2(v_texcoord0.x + textureShiftBuffer.postUV0,
            v_texcoord0.y + textureShiftBuffer.postUV1)
    );
    float blendFactor = clamp(
        (textureShiftBuffer.globalAlpha
        - ((1.0 - textureShiftBuffer.localShiftLength) * v_textureShift.x))
        / textureShiftBuffer.localShiftLength, 0.0, 1.0);
    vec4 albedo = mix(preFrameSample, postFrameSample, blendFactor);
#if GEOMETRY_PREPASS_ALPHA_TEST_PASS
    if (albedo.a < 0.5) discard;
#endif
    albedo.rgb *= v_color0.rgb;

    vec2 adjustedUV = vec2(v_texcoord0.x + textureShiftBuffer.postUV0,
        v_texcoord0.y + textureShiftBuffer.postUV1);
    int pbrTextureId = textureShiftBuffer.packedPBRId & 0xFFFF;

    if (blendFactor < 0.5) {
        adjustedUV = vec2(v_texcoord0.x + textureShiftBuffer.preUV0,
            v_texcoord0.y + textureShiftBuffer.preUV1);
        pbrTextureId = (textureShiftBuffer.packedPBRId >> 16) & 0xFFFF;
    }

    vec3 normal = gl_FrontFacing ? -v_normal : v_normal;
    normal = normalize(normal);
    vec4 mers = vec4(0.0, 0.0, 1.0, 0.0);
    texturePBRMaterials(s_MatTexture, pbrTextureId, adjustedUV, v_tangent, v_bitangent,
        normal, mers);

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
}
#endif
#endif //SHADER_STAGE__FRAGMENT
