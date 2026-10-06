#include "lib/gbuffer_utils.glsl"

///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
uniform mat4 u_viewProj;
uniform mat4 u_model[BGFX_CONFIG_MAX_BONES];
uniform vec4 SunDir;
uniform vec4 MoonDir;
uniform vec4 SunColor;

#include "lib/atmosphere.glsl"

in vec4 a_color0;
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
#if FORWARD_PBR_TRANSPARENT_PASS
layout(location = 2) flat out vec3 v_absorbColor;
layout(location = 3) flat out vec3 v_scatterColor;
layout(location = 4) out vec3 v_worldPos;
layout(location = 5) out vec4 v_clipPos;
layout(location = 6) out vec3 v_lightColor;
layout(location = 7) out vec2 v_lightmapUV;
#endif

void main() {
#if INSTANCING__ON
    vec3 worldPos = (instanceMatrix(i_data1, i_data2, i_data3) * vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = (u_model[0] * vec4(a_position, 1.0)).xyz;
#endif
    vec4 clipPos = (u_viewProj * vec4(worldPos, 1.0));

    v_color0 = a_color0;
    v_texcoord0 = a_texcoord0;
#if FORWARD_PBR_TRANSPARENT_PASS
    v_clipPos = clipPos;
    v_worldPos = worldPos;
    uvec2 data16 = uvec2(roundEven(a_texcoord1 * 65535.0)) & 0xFFFFu;
    uint lo = data16.g & 0xFFu;
    v_lightColor = vec3(data16.r >> 8, data16.r & 0xFFu, data16.g >> 8) / 255.0;
    v_lightmapUV = vec2(uvec2(lo >> 4, lo) & 15u) / 15.0;
    vec3 absorbColor, scatterColor;
    calcAtmLighting(SunDir.xyz, MoonDir.xyz, SunColor.r, absorbColor, scatterColor);
    v_absorbColor = absorbColor;
    v_scatterColor = scatterColor;
#endif

    gl_Position = clipPos;
}
#endif //SHADER_STAGE__VERTEX

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
SAMPLER2D(s_ParticleTexture);

layout(location = 0) in vec4 v_color0;
layout(location = 1) in vec2 v_texcoord0;

#if FORWARD_PBR_TRANSPARENT_PASS
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
uniform vec4 CameraIsUnderwater;
uniform vec4 MERSUniforms;
uniform vec4 PBRTextureFlags;
uniform vec4 SunDir;
uniform vec4 MoonDir;
uniform mat4 u_model[BGFX_CONFIG_MAX_BONES];

SAMPLER2D(s_MERSTexture);
SAMPLER2D(s_NormalTexture);
SAMPLER2D(s_PreviousFrameAverageLuminance);

#include "lib/materials.glsl"
#include "lib/forward_shading.glsl"

layout(location = 2) flat in vec3 v_absorbColor;
layout(location = 3) flat in vec3 v_scatterColor;
layout(location = 4) in vec3 v_worldPos;
layout(location = 5) in vec4 v_clipPos;
layout(location = 6) in vec3 v_lightColor;
layout(location = 7) in vec2 v_lightmapUV;
#endif

out vec4 fragColor;

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
    fragColor = albedo;
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

    vec3 normal = ((pbrTextureFlags & kPBRHasNormalTexture) == kPBRHasNormalTexture)
        ? (u_model[0] * vec4(texture(s_NormalTexture, v_texcoord0).rgb * 2.0 - 1.0, 0.0)).xyz
        : vec3(0.0);

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
        v_lightColor,
        alwaysLit,
        v_scatterColor,
        v_absorbColor,
        v_lightmapUV
    );

    outColor = preExposeLighting(outColor * EXPOSURE_MULTIPLIER,
        texture(s_PreviousFrameAverageLuminance, vec2(0.5)).r);

    fragColor = vec4(outColor, albedo.a);
#endif
}
#endif //SHADER_STAGE__FRAGMENT
