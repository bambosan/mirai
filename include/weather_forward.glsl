#include "./lib/taau_util.glsl"

#if BGFX_SHADER_TYPE_VERTEX
uniform highp vec4 Dimensions;
uniform highp vec4 ViewPosition;
uniform highp vec4 UVOffsetAndScale;
uniform highp vec4 Velocity;
uniform highp vec4 PositionBaseOffset;
uniform highp vec4 PositionForwardOffset;
uniform highp vec4 PrevPositionForwardOffset;

vec3 calcWorldPos(vec3 position) {
    vec3 p = position + PositionBaseOffset.xyz;
    p = p - 30.0 * trunc(p / 30.0);
    p -= 15.0;
    p += PositionForwardOffset.xyz;
    return p;
}

void main() {
    vec3 worldPos = calcWorldPos(a_position);
    vec4 projPosBottom = jitterVertexPosition(worldPos);
    vec3 worldPosTop = worldPos + (Velocity.xyz * Dimensions.y);
    vec4 projPosTop = jitterVertexPosition(worldPosTop);

    vec2 projPosUpDir = (projPosTop.xy / projPosTop.w) - (projPosBottom.xy / projPosBottom.w);
    vec2 projPosRightDir = normalize(vec2(-projPosUpDir.y, projPosUpDir.x));

    gl_Position = mix(projPosTop, projPosBottom, a_texcoord0.y);
    gl_Position.xy += (0.5 - a_texcoord0.x) * projPosRightDir * Dimensions.x;

    v_texcoord0 = UVOffsetAndScale.xy + (a_texcoord0 * UVOffsetAndScale.zw);
#if NO_VARIETY__OFF
    v_texcoord0.x += a_color0.x * 255.0 * UVOffsetAndScale.z;
#endif
    v_occlusionUV = (worldPos.xz + ViewPosition.xz) / 64.0 + 0.5;
    v_occlusionHeight = (worldPos.y + (ViewPosition.y - 0.5)) / 255.0;
    v_worldPos = worldPos;
    v_prevWorldPos = worldPos + PrevPositionForwardOffset.xyz;
}
#endif

#if BGFX_SHADER_TYPE_FRAGMENT
uniform highp vec4 OcclusionHeightOffset;

SAMPLER2D_HIGHP_AUTOREG(s_LightingTexture);
SAMPLER2D_HIGHP_AUTOREG(s_OcclusionTexture);
SAMPLER2D_HIGHP_AUTOREG(s_WeatherTexture);

#if FORWARD_PBR_TRANSPARENT_PASS
#include "./lib/common.glsl"
SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);
#endif

bool isOccluded(vec2 occlusionUV, float occlusionHeight, float occlusionHeightThreshold) {
#if NO_OCCLUSION__ON
    return false;
#else
    if (!(occlusionUV.x >= 0.0 && occlusionUV.x <= 1.0 && occlusionUV.y >= 0.0 && occlusionUV.y <= 1.0)) return false;
#if FLIP_OCCLUSION__ON
    return occlusionHeight < occlusionHeightThreshold;
#else
    return occlusionHeight > occlusionHeightThreshold;
#endif
#endif
}

vec2 calculateOcclusionAndLightingUV(vec2 occlusionUV, float occlusionHeight) {
#if NO_OCCLUSION__ON
    return vec2_splat(1.0);
#else
    vec4 o = texture2D(s_OcclusionTexture, occlusionUV);
    float occlusionLuminance = o.r;
    float occlusionHeightThreshold = o.g + (o.b * 255.0) - (OcclusionHeightOffset.x / 255.0);
    if (isOccluded(occlusionUV, occlusionHeight, occlusionHeightThreshold)) return vec2_splat(0.0);
    float fade = saturate(occlusionLuminance - ((occlusionHeight - occlusionHeightThreshold) * 25.0) * occlusionLuminance);
    return vec2(fade, 0.5);
#endif
}

void main() {
    vec4 albedo = texture2D(s_WeatherTexture, v_texcoord0);

#if FORWARD_PBR_TRANSPARENT_PASS
    vec2 lighting = calculateOcclusionAndLightingUV(v_occlusionUV, v_occlusionHeight);
    albedo.rgb = pow(albedo.rgb, vec3_splat(2.2));
    albedo.rgb = saturation(albedo.rgb, 0.0);

    vec3 blockAmbient = BLOCK_LIGHT_COLOR * uv1x2lig(lighting.r) * BLOCK_LIGHT_INTENSITY;
    vec3 outColor = albedo.rgb * max(blockAmbient, vec3_splat(0.05));
    outColor = preExposeLighting(outColor, texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r);

    gl_FragColor = vec4(outColor, albedo.a * lighting.g);

#elif MOTION_ONLY_PASS
    if (albedo.a < 0.5) discard;

    vec4 o = texture2D(s_OcclusionTexture, v_occlusionUV);
    float occlusionHeightThreshold = o.g + o.b * 255.0 - OcclusionHeightOffset.x / 255.0;
    bool inside = v_occlusionUV.x >= 0.0 && v_occlusionUV.x <= 1.0 && v_occlusionUV.y >= 0.0 && v_occlusionUV.y <= 1.0;
    if (inside && v_occlusionHeight > occlusionHeightThreshold) discard;

    vec2 motionVec = (distance(v_worldPos, v_prevWorldPos - u_prevWorldPosOffset.xyz) > 27.0) ? calculateMotionVector(v_worldPos, v_worldPos) : calculateMotionVector(v_worldPos, v_prevWorldPos - u_prevWorldPosOffset.xyz);
    gl_FragData[0] = vec4(1.0, 1.0, motionVec);
#else

    gl_FragColor = vec4_splat(0.0);
#endif
}
#endif
