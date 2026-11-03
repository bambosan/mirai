///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
#if FORWARD_PBR_TRANSPARENT_SKY_PROBE_PASS
void main() {
    gl_Position = vec4(0.0);
}
#else
uniform mat4 u_model[BGFX_CONFIG_MAX_BONES];
uniform mat4 u_viewProj;

#include "lib/gbuffer_utils.glsl"

in vec4 a_color0;
in vec3 a_position;
in vec2 a_texcoord0;
#if INSTANCING__ON
in vec4 i_data1;
in vec4 i_data2;
in vec4 i_data3;
#endif

layout(location = 0) out vec4 v_color0;
layout(location = 1) out vec4 v_clipPos;
#if VOLUMETRIC_CLOUDS_ENABLED
layout(location = 2) out vec3 v_worldPos;
#endif

void main() {
#if INSTANCING__ON
    vec3 worldPos = (instanceMatrix(i_data1, i_data2, i_data3) * vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = (u_model[0] * vec4(a_position, 1.0)).xyz;
#endif
    vec4 clipPos = u_viewProj * vec4(worldPos, 1.0);
    v_color0 = a_color0;
    v_clipPos = clipPos;
#if VOLUMETRIC_CLOUDS_ENABLED
    v_worldPos = worldPos;
#endif
    gl_Position = clipPos;
}
#endif
#endif //SHADER_STAGE__VERTEX

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
#if FORWARD_PBR_TRANSPARENT_SKY_PROBE_PASS
out vec4 fragColor;
void main() {
    fragColor = vec4(0.0);
}
#else
uniform vec4 Time;
uniform vec4 WorldOrigin;
uniform vec4 StarsColor;
uniform vec4 SunColor;
uniform vec4 VolumeDimensions;
uniform vec4 VolumeNearFar;
uniform vec4 VolumeScatteringEnabledAndPointLightVolumetricsEnabled;
uniform mat4 u_invProj;

SAMPLER2D(s_PreviousFrameAverageLuminance);
SAMPLER2DARRAY(s_ScatteringBuffer);

#include "lib/clouds.glsl"
#include "lib/froxel_utils.glsl"

layout(location = 0) in vec4 v_color0;
layout(location = 1) in vec4 v_clipPos;
#if VOLUMETRIC_CLOUDS_ENABLED
layout(location = 2) in vec3 v_worldPos;
#endif

out vec4 fragColor;

void main() {
    vec4 outColor = v_color0 * StarsColor;
    outColor.rgb = toLinear(outColor.rgb);

#if VOLUMETRIC_CLOUDS_ENABLED
    vec3 worldDir = normalize(v_worldPos);
    float dither = texelFetch(s_CausticsTexture, ivec3(ivec2(gl_FragCoord.xy) % 256, 1), 0).r;
    CloudSetup cloudSetup = calcCloudSetup(worldDir.y, -WorldOrigin.y);
    float cloudTransmittance = calcCloudTransmittanceOnly(
        worldDir, 0.0, dither, Time.x, StarsColor.r, false, cloudSetup);
    outColor *= cloudTransmittance;
#endif

    if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.x > 0.0) {
        vec3 projPos = v_clipPos.xyz / v_clipPos.w;
        vec3 uvw = ndcToVolume(VolumeNearFar.xy, projPos, u_invProj);
        vec4 volumetricFog = sampleVolume(
            s_ScatteringBuffer, uvw, VolumeDimensions.z);
        outColor *= volumetricFog.a;
    }

    outColor.rgb = preExposeLighting(outColor.rgb, texture(s_PreviousFrameAverageLuminance,
        vec2(0.5)).r);
    fragColor = outColor;
}
#endif
#endif //SHADER_STAGE__FRAGMENT
