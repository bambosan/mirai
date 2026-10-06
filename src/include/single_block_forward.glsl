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
uniform vec4 SunDir;
uniform vec4 MoonDir;
uniform vec4 SunColor;

#include "lib/atmosphere.glsl"

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
#if INSTANCING__ON
in vec4 i_data1;
in vec4 i_data2;
in vec4 i_data3;
#endif

#if FORWARD_PBR_ALPHA_TEST_PASS || FORWARD_PBR_OPAQUE_PASS || FORWARD_PBR_TRANSPARENT_PASS
layout(location = 0) flat out vec3 v_absorbColor;
layout(location = 1) flat out vec3 v_scatterColor;
layout(location = 2) flat out int v_pbrTextureId;
layout(location = 3) out vec4 v_color0;
layout(location = 4) out vec3 v_tangent;
layout(location = 5) out vec3 v_bitangent;
layout(location = 6) out vec3 v_normal;
layout(location = 7) out vec3 v_worldPos;
layout(location = 8) out vec4 v_clipPos;
layout(location = 9) out vec2 v_texcoord0;
#endif

void main() {
#if INSTANCING__ON
    vec3 worldPos = (instanceMatrix(i_data1, i_data2, i_data3) * vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = (u_model[0] * vec4(a_position, 1.0)).xyz;
#endif

#if FORWARD_PBR_ALPHA_TEST_PASS || FORWARD_PBR_OPAQUE_PASS || FORWARD_PBR_TRANSPARENT_PASS
    v_pbrTextureId = int(a_texcoord4) & 0xFFFF;
    v_texcoord0 = unpackTexcoord0(a_texcoord0);
    v_normal = (u_model[0] * vec4(a_normal.xyz, 0.0)).xyz;
    v_tangent = (u_model[0] * vec4(a_tangent.xyz, 0.0)).xyz;
    v_bitangent = (u_model[0] * vec4(cross(a_normal.xyz, a_tangent.xyz) * a_tangent.w, 0.0)).xyz;
    v_worldPos = worldPos;
    v_color0 = a_color0;
    v_clipPos = u_viewProj * vec4(worldPos, 1.0);
    vec3 absorbColor, scatterColor;
    calcAtmLighting(SunDir.xyz, MoonDir.xyz, SunColor.r, absorbColor, scatterColor);
    v_absorbColor = absorbColor;
    v_scatterColor = scatterColor;

    gl_Position = jitterVertexPosition(SubPixelOffset, worldPos, u_view, u_proj);
#else
#if RENDER_AS_BILLBOARDS__ON
    worldPos = applyBillboard(worldPos + 0.5, a_color0.rgb);
#endif
    gl_Position = u_viewProj * vec4(worldPos, 1.0);
#endif
}
#endif //SHADER_STAGE__VERTEX

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
#if DEPTH_ONLY_ALPHA_TEST_PASS || DEPTH_ONLY_OPAQUE_PASS || OPAQUE_PASS
out vec4 fragData0;
void main() {
    fragData0 = vec4(1.0);
}
#else
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
uniform vec4 TileLightIntensity;
uniform vec4 BlockLightColor;

SAMPLER2D(s_MatTexture);
SAMPLER2D(s_PreviousFrameAverageLuminance);

#include "lib/materials.glsl"
#include "lib/forward_shading.glsl"

layout(location = 0) flat in vec3 v_absorbColor;
layout(location = 1) flat in vec3 v_scatterColor;
layout(location = 2) flat in int v_pbrTextureId;
layout(location = 3) in vec4 v_color0;
layout(location = 4) in vec3 v_tangent;
layout(location = 5) in vec3 v_bitangent;
layout(location = 6) in vec3 v_normal;
layout(location = 7) in vec3 v_worldPos;
layout(location = 8) in vec4 v_clipPos;
layout(location = 9) in vec2 v_texcoord0;

out vec4 fragData0;

void main() {
    vec3 normal = gl_FrontFacing ? -v_normal : v_normal;
    normal = normalize(normal);
    vec4 mers = vec4(0.0, 0.0, 1.0, 0.0);
    texturePBRMaterials(s_MatTexture, v_pbrTextureId, v_texcoord0, v_tangent, v_bitangent,
        normal, mers);
    if (v_normal.y > 0.0)
        mers.b = mix(smoothstep(1.0, 0.6, TileLightIntensity.y), mers.b, SunColor.r);

    vec4 albedo = texture(s_MatTexture, v_texcoord0);
    vec3 nColor = normalize(v_color0.rgb);
    float nColorAvg = colorAvg(nColor);
    float vanillaAO = colorAvg(v_color0.rgb);
    if (any(notEqual(nColor.ggb, nColor.brr))) {
        albedo.rgb *= nColor;
        vanillaAO /= nColorAvg;
    }
    albedo.rgb *= nColorAvg;
    albedo.rgb = toLinear(albedo.rgb);

    vec3 f0 = mix(DEFAULT_F0, albedo.rgb, mers.r);

    vec3 alwaysLit = albedo.rgb * mers.g * EMISSIVE_MATERIAL_INTENSITY;
    vec3 projPos = v_clipPos.xyz / v_clipPos.w;

    vec3 outColor = applyForwardShading(
        mers,
        f0,
        vec4(albedo.rgb, vanillaAO),
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
}
#endif
#endif //SHADER_STAGE__FRAGMENT
