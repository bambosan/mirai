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

layout(location = 0) out vec4 v_clipPos;
layout(location = 1) out vec3 v_worldPos;
layout(location = 2) out vec2 v_texcoord0;

void main() {
#if INSTANCING__ON
    vec3 worldPos = (instanceMatrix(i_data1, i_data2, i_data3) * vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = (u_model[0] * vec4(a_position * 2.0, 1.0)).xyz;
#endif
    vec4 clipPos = u_viewProj * vec4(worldPos, 1.0);
    v_clipPos = clipPos;
    v_texcoord0 = a_texcoord0;
    v_worldPos = worldPos * 0.5;
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
uniform vec4 MoonDir;
uniform vec4 SunDir;
uniform vec4 SunMoonColor;
uniform vec4 VolumeDimensions;
uniform vec4 VolumeNearFar;
uniform vec4 VolumeScatteringEnabledAndPointLightVolumetricsEnabled;
uniform mat4 u_invProj;

SAMPLER2D(s_SunMoonTexture);
SAMPLER2D(s_PreviousFrameAverageLuminance);
SAMPLER2DARRAY(s_ScatteringBuffer);

#include "lib/atmosphere.glsl"
#include "lib/froxel_utils.glsl"

layout(location = 0) in vec4 v_clipPos;
layout(location = 1) in vec3 v_worldPos;
layout(location = 2) in vec2 v_texcoord0;

out vec4 fragColor;

void main() {
    vec3 worldDir = normalize(v_worldPos);

    vec3 cRayleigh, cMie, cOzone;
    atmConstant(SunMoonColor.r, cRayleigh, cMie, cOzone);
    AtmosphereParams atmParams = AtmosphereParams(
        cRayleigh,
        cMie,
        cOzone,
        worldDir,
        vec3(0.0),
        1e10,
        1.0,
        1.0,
        SunMoonColor.r
    );
    vec4 transmittance;
    vec3 unused = calcAtmosphere(atmParams, transmittance);

    float disc  = sqrt(smoothstep(cos(0.00436 * 10.0), 1.0, dot(worldDir, SunDir.xyz)));
    float tsmLum = luminance(transmittance.rgb);
    vec3 outColor = disc * pow(tsmLum, 1.5) * transmittance.rgb * transmittance.a
        * SUN_RADIANCE_MULTIPLIER * 100.0;

    if (dot(worldDir, MoonDir.xyz) > 0.0) {
        vec3 tex = toLinear(texture(s_SunMoonTexture, v_texcoord0).rgb);
        float texlum = luminance(tex);
        outColor = step(0.05, texlum) * texlum * transmittance.rgb * transmittance.a
            * MOON_RADIANCE_MULTIPLIER * 5.0;
    }

    if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.x > 0.0) {
        vec3 projPos = v_clipPos.xyz / v_clipPos.w;
        vec3 uvw = ndcToVolume(VolumeNearFar.xy, projPos, u_invProj);
        vec4 volumetricFog = sampleVolume(s_ScatteringBuffer, uvw, VolumeDimensions.z);
        outColor *= volumetricFog.a;
    }

    outColor *= SunMoonColor.r;

    outColor.rgb = preExposeLighting(outColor.rgb * EXPOSURE_MULTIPLIER,
        texture(s_PreviousFrameAverageLuminance, vec2(0.5)).r);
    fragColor = vec4(outColor, 1.0);
}
#endif
#endif //SHADER_STAGE__FRAGMENT
