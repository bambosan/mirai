#include "lib/gbuffer_utils.glsl"

///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
uniform vec4 SunDir;
uniform vec4 MoonDir;
uniform vec4 SunColor;
uniform mat4 u_viewProj;
uniform mat4 u_view;
uniform mat4 u_model[BGFX_CONFIG_MAX_BONES];

#include "lib/atmosphere.glsl"

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

layout(location = 0) flat out vec3 v_absorbColor;
layout(location = 1) flat out vec3 v_scatterColor;
layout(location = 2) out vec4 v_color0;
layout(location = 3) out vec3 v_worldPos;
layout(location = 4) out vec4 v_clipPos;
#if USE_TEXTURES__ON
layout(location = 5) out vec2 v_texcoord0;
#endif

void main() {
#if INSTANCING__ON
    vec3 worldPos = (instanceMatrix(i_data1, i_data2, i_data3) * vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = (u_model[0] * vec4(a_position, 1.0)).xyz;
#endif
    vec4 clipPos = u_viewProj * vec4(worldPos, 1.0);

    v_clipPos = clipPos;
    v_color0 = a_color0;
    v_worldPos = worldPos;
    vec3 absorbColor, scatterColor;
    calcAtmLighting(SunDir.xyz, MoonDir.xyz, SunColor.r, absorbColor, scatterColor);
    v_absorbColor = absorbColor;
    v_scatterColor = scatterColor;
#if USE_TEXTURES__ON
    v_texcoord0 = a_texcoord0;
#endif

    gl_Position = clipPos;
}
#endif //SHADER_STAGE__VERTEX

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
uniform vec4 FogColor;
uniform vec4 DirectionalLightSourceWorldSpaceDirection;
uniform vec4 FogAndDistanceControl;
uniform vec4 RenderChunkFogAlpha;
uniform vec4 SunColor;
uniform vec4 SunDir;
uniform vec4 MoonDir;
uniform vec4 FogSkyBlend;
uniform vec4 AmbientLightParams;
uniform vec4 VolumeDimensions;
uniform vec4 VolumeNearFar;
uniform vec4 VolumeScatteringEnabledAndPointLightVolumetricsEnabled;
uniform mat4 u_invViewProj;
uniform mat4 u_invProj;
uniform vec4 CameraIsUnderwater;
uniform vec4 CameraLightIntensity;
uniform vec4 CausticsParameters;
uniform vec4 BlockLightColor;
uniform vec4 TileLightIntensity;
uniform vec4 CurrentColor;
uniform vec4 MERSUniforms;
uniform vec4 IBLParameters;
uniform vec4 ConvolutionType;
uniform vec4 LastSpecularIBLIdx;

SAMPLER2D(s_MatTexture);
SAMPLER2D(s_PreviousFrameAverageLuminance);

#include "lib/materials.glsl"
#include "lib/gbuffer_utils.glsl"
#include "lib/forward_shading.glsl"

layout(location = 0) flat in vec3 v_absorbColor;
layout(location = 1) flat in vec3 v_scatterColor;
layout(location = 2) in vec4 v_color0;
layout(location = 3) in vec3 v_worldPos;
layout(location = 4) in vec4 v_clipPos;
#if USE_TEXTURES__ON
layout(location = 5) in vec2 v_texcoord0;
#endif

layout(location = 0) out vec4 fragData0;
layout(location = 1) out vec4 fragData1;
layout(location = 2) out vec4 fragData2;

void main() {
#if USE_TEXTURES__ON
    vec4 albedo = texture(s_MatTexture, v_texcoord0);
    if (albedo.a < 0.5) discard;
#else
    vec4 albedo = vec4(1.0);
#endif
    albedo *= CurrentColor * v_color0;
    albedo.rgb = toLinear(albedo.rgb * 0.5);

    vec3 normal = vec3(0.0, 0.0, 1.0);
    vec3 f0 = mix(DEFAULT_F0, albedo.rgb, MERSUniforms.r);

    vec3 alwaysLit = albedo.rgb * MERSUniforms.g * EMISSIVE_MATERIAL_INTENSITY;
    vec3 projPos = v_clipPos.xyz / v_clipPos.w;

    vec3 outColor = applyForwardShading(
        MERSUniforms,
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
    fragData1 = vec4(0.0);
    fragData2 = vec4(0.0);
}
#endif //SHADER_STAGE__FRAGMENT
