#include "lib/taau_utils.glsl"

///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
uniform vec4 Dimensions;
uniform vec4 ViewPosition;
uniform vec4 UVOffsetAndScale;
uniform vec4 Velocity;
uniform vec4 PositionBaseOffset;
uniform vec4 PositionForwardOffset;
uniform vec4 PrevPositionForwardOffset;
uniform vec4 SunDir;
uniform vec4 MoonDir;
uniform vec4 SunColor;
uniform mat4 u_view;
uniform mat4 u_proj;
uniform vec4 SubPixelOffset;

#include "lib/atmosphere.glsl"

in vec4 a_color0;
in vec3 a_position;
in vec2 a_texcoord0;

#if FORWARD_PBR_TRANSPARENT_PASS
layout(location = 0) out vec2 v_occlusionUV;
layout(location = 1) out float v_occlusionHeight;
layout(location = 2) out vec2 v_texcoord0;
layout(location = 3) flat out vec3 v_absorbColor;
#endif
#if MOTION_ONLY_PASS
#if NO_OCCLUSION__OFF
layout(location = 0) out vec2 v_occlusionUV;
layout(location = 1) out float v_occlusionHeight;
#endif
layout(location = 2) out vec2 v_texcoord0;
layout(location = 3) out vec3 v_worldPos;
layout(location = 4) out vec3 v_prevWorldPos;
#endif

void main() {
    vec3 worldPos = mod(a_position + PositionBaseOffset.xyz, 30.0)
        - 15.0 + PositionForwardOffset.xyz;
    vec3 worldPosTop = worldPos + Velocity.xyz * Dimensions.y;
    vec4 projPosBottom = jitterVertexPosition(SubPixelOffset, worldPos, u_view, u_proj);
    vec4 projPosTop = jitterVertexPosition(SubPixelOffset, worldPosTop, u_view, u_proj);
    vec2 projPosUpDir = (projPosTop.xy / projPosTop.w) - (projPosBottom.xy / projPosBottom.w);
    vec2 projPosRightDir = normalize(vec2(-projPosUpDir.y, projPosUpDir.x));

#if FORWARD_PBR_TRANSPARENT_PASS || MOTION_ONLY_PASS
    v_texcoord0 = UVOffsetAndScale.xy + (a_texcoord0 * UVOffsetAndScale.zw);
#if NO_VARIETY__OFF
    v_texcoord0.x += a_color0.x * 255.0 * UVOffsetAndScale.z;
#endif
#if FORWARD_PBR_TRANSPARENT_PASS
    v_occlusionUV = (worldPos.xz + ViewPosition.xz) / 64.0 + 0.5;
    v_occlusionHeight = (worldPos.y + (ViewPosition.y - 0.5)) / 255.0;
    vec3 absorbColor, scatterColor;
    calcAtmLighting(SunDir.xyz, MoonDir.xyz, SunColor.r, absorbColor, scatterColor);
    v_absorbColor = absorbColor;
#endif //FORWARD_PBR_TRANSPARENT_PASS
#if MOTION_ONLY_PASS
#if NO_OCCLUSION__OFF
    v_occlusionUV = (worldPos.xz + ViewPosition.xz) / 64.0 + 0.5;
    v_occlusionHeight = (worldPos.y + (ViewPosition.y - 0.5)) / 255.0;
#endif //NO_OCCLUSION__OFF
    v_worldPos = worldPos;
    v_prevWorldPos = worldPos + PrevPositionForwardOffset.xyz;
#endif //MOTION_ONLY_PASS
#endif

    gl_Position = mix(projPosTop, projPosBottom, a_texcoord0.y);
    gl_Position.xy += (0.5 - a_texcoord0.x) * projPosRightDir * Dimensions.x;
}
#endif //SHADER_STAGE__VERTEX

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
uniform vec4 OcclusionHeightOffset;
uniform vec4 u_prevWorldPosOffset;
uniform mat4 u_viewProj;
uniform mat4 u_prevViewProj;

SAMPLER2D(s_LightingTexture);
SAMPLER2D(s_OcclusionTexture);
SAMPLER2D(s_WeatherTexture);

#if FORWARD_PBR_TRANSPARENT_PASS
SAMPLER2D(s_PreviousFrameAverageLuminance);
#endif

#include "lib/common.glsl"

bool isOccluded(vec2 occlusionUV, float occlusionHeight, float occlusionHeightThreshold) {
    bool occlusionUv = occlusionUV.x >= 0.0 && occlusionUV.x <= 1.0
        && occlusionUV.y >= 0.0 && occlusionUV.y <= 1.0;
#if FLIP_OCCLUSION__ON
    return (occlusionUv && occlusionHeight > occlusionHeightThreshold);
#else
    return (occlusionUv && occlusionHeight < occlusionHeightThreshold);
#endif
}

#if FORWARD_PBR_TRANSPARENT_PASS
layout(location = 0) in vec2 v_occlusionUV;
layout(location = 1) in float v_occlusionHeight;
layout(location = 2) in vec2 v_texcoord0;
layout(location = 3) flat in vec3 v_absorbColor;
#endif
#if MOTION_ONLY_PASS
#ifdef NO_OCCLUSION__OFF
layout(location = 0) in vec2 v_occlusionUV;
layout(location = 1) in float v_occlusionHeight;
#endif
layout(location = 2) in vec2 v_texcoord0;
layout(location = 3) in vec3 v_worldPos;
layout(location = 4) in vec3 v_prevWorldPos;
#endif

out vec4 fragData0;

void main() {
#if FORWARD_PBR_TRANSPARENT_PASS
    vec4 albedo = texture(s_WeatherTexture, v_texcoord0);
    albedo.rgb = toLinear(albedo.rgb);
#if NO_VARIETY__OFF
    // rain particles
    albedo.rgb = saturation(albedo.rgb, 0.0);
    albedo.a *= 0.1;
#endif

    uvec4 bytes = uvec4(round(texture(s_OcclusionTexture, v_occlusionUV) * 255.0));
    float occHeightThreshold = (float((bytes.x | (bytes.y << 8)) & 1023u)
        + OcclusionHeightOffset.x) / 255.0;
    float lintensity = float(bytes.y >> 2) / 63.0 * 6.0;
    vec3 lightColor = vec3(bytes.z >> 4, bytes.w & 15u, bytes.w >> 4) / 15.0 * lintensity;
    vec3 blockAmbient = lightColor - lightColor
        * clamp(v_occlusionHeight - occHeightThreshold, 0.0, 1.0) * 25.0;

    vec3 outColor = albedo.rgb * luminance(v_absorbColor) * (1.0 + blockAmbient);
    outColor = preExposeLighting(outColor, texture(s_PreviousFrameAverageLuminance, vec2(0.5)).r);

    fragData0 = vec4(outColor, albedo.a);
#if NO_OCCLUSION__OFF
    if (isOccluded(v_occlusionUV, v_occlusionHeight, occHeightThreshold))
        fragData0 = vec4(0.0);
#endif

#elif MOTION_ONLY_PASS
    vec4 albedo = texture(s_WeatherTexture, v_texcoord0);
    if (albedo.a < 0.5) discard;
#ifdef NO_OCCLUSION__OFF
    uvec4 bytes = uvec4(texture(s_OcclusionTexture, v_occlusionUV) * 255.0);
    float occHeightThreshold = (float((bytes.x | (bytes.y << 8)) & 1023u)
        + OcclusionHeightOffset.x) / 255.0;
    if (isOccluded(v_occlusionUV, v_occlusionHeight, occHeightThreshold)) discard;
#endif //NO_OCCLUSION__OFF
    vec2 motionVec = (distance(v_worldPos, v_prevWorldPos - u_prevWorldPosOffset.xyz) > 27.0)
        ? calculateMotionVector(v_worldPos, v_worldPos, u_viewProj, u_prevViewProj)
        : calculateMotionVector(v_worldPos, v_prevWorldPos - u_prevWorldPosOffset.xyz,
            u_viewProj, u_prevViewProj);
    fragData0 = vec4(1.0, 1.0, motionVec);
#else //!MOTION_ONLY_PASS
    fragData0 = vec4(0.0);
#endif //FORWARD_PBR_TRANSPARENT_PASS
}
#endif //SHADER_STAGE__FRAGMENT
