#include "lib/atmosphere.glsl"

///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
#if FALLBACK_PASS
void main() {
    gl_Position = vec4(0.0);
}
#else
uniform vec4 SunDir;
uniform vec4 MoonDir;
uniform vec4 SunColor;

in vec3 a_position;
in vec2 a_texcoord0;

layout(location = 0) flat out vec3 v_absorbColor;
layout(location = 1) out vec2 v_texcoord0;
layout(location = 2) out vec2 v_projPos;

void main() {
    v_texcoord0 = a_texcoord0;
    v_projPos = a_position.xy * 2.0 - 1.0;
    vec3 absorbColor, scatterColor;
    calcAtmLighting(SunDir.xyz, MoonDir.xyz, SunColor.r, absorbColor, scatterColor);
    v_absorbColor = absorbColor;
    gl_Position = vec4(a_position.xy * 2.0 - 1.0, a_position.z, 1.0);
}
#endif
#endif //SHADER_STAGE__VERTEX

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
#if FALLBACK_PASS
out vec4 fragColor;
void main() {
    fragColor = vec4(0.0);
}
#else
uniform vec4 ClampViewVectors;
uniform vec4 MoonDir;
uniform vec4 SunDir;
uniform vec4 DirectionalLightSourceWorldSpaceDirection;
uniform vec4 Time;
uniform vec4 WorldOrigin;
uniform vec4 SkyProbeUVFadeParameters;
uniform vec4 CurrentFace;
uniform vec4 SunColor;
uniform mat4 u_invViewProj;

SAMPLER2D(s_SceneDepth);

#include "lib/clouds.glsl"
#include "lib/space_transf.glsl"

layout(location = 0) flat in vec3 v_absorbColor;
layout(location = 1) in vec2 v_texcoord0;
layout(location = 2) in vec2 v_projPos;

out vec4 fragColor;

void main() {
    float depth = sampleDepth(s_SceneDepth, v_texcoord0);

    vec3 projPos = vec3(v_projPos, depth);
    vec3 worldPos = projToWorld(projPos, u_invViewProj);
    vec3 worldDir = normalize(worldPos);
    if (worldDir.y < 0.1 && ClampViewVectors.x > 0.0)
        worldDir = normalize(vec3(worldDir.x, 0.1, worldDir.z));

    vec3 outColor = calcAtmSky(worldDir, SunDir.xyz, MoonDir.xyz, SunColor.r);

    vec3 cloudColor = SunDir.y > 0.0 ? v_absorbColor : v_absorbColor * SunColor.r * 0.5;
    applyCirrusClouds(outColor, worldDir, -WorldOrigin.xyz,
        DirectionalLightSourceWorldSpaceDirection.xyz, cloudColor, Time.x, false);

    if (int(CurrentFace.x) == 3) {
        outColor *= SkyProbeUVFadeParameters.z;
    } else if(int(CurrentFace.x) != 2) {
        float fadeRange = (SkyProbeUVFadeParameters.x - SkyProbeUVFadeParameters.y) + EPSILON;
        float fade = (clamp(
            projPos.y * 0.5 + 0.5,
            SkyProbeUVFadeParameters.y,
            SkyProbeUVFadeParameters.x
        ) - SkyProbeUVFadeParameters.y) / fadeRange;
        outColor *= max(fade, SkyProbeUVFadeParameters.z);
    }

    fragColor = vec4(outColor, 1.0);
}
#endif
#endif //SHADER_STAGE__FRAGMENT
