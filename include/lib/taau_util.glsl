#ifndef TAAU_UTIL_INCLUDE
#define TAAU_UTIL_INCLUDE

#if BGFX_SHADER_TYPE_VERTEX

uniform vec4 SubPixelOffset;

vec4 jitterVertexPosition(vec3 worldPos) {
    mat4 offsetProj = u_proj;
#if BGFX_SHADER_LANGUAGE_GLSL
    offsetProj[2][0] += SubPixelOffset.x;
    offsetProj[2][1] -= SubPixelOffset.y;
#else
    offsetProj[0][2] += SubPixelOffset.x;
    offsetProj[1][2] -= SubPixelOffset.y;
#endif
    return mul(offsetProj, mul(u_view, vec4(worldPos, 1.0)));
}

#else

vec2 calculateMotionVector(vec3 worldPosition, vec3 previousWorldPosition) {
    vec4 screenSpacePos = mul(u_viewProj, vec4(worldPosition, 1.0));
    screenSpacePos /= screenSpacePos.w;
    screenSpacePos = screenSpacePos * 0.5 + 0.5;
    vec4 prevScreenSpacePos = mul(u_prevViewProj, vec4(previousWorldPosition, 1.0));
    prevScreenSpacePos /= prevScreenSpacePos.w;
    prevScreenSpacePos = prevScreenSpacePos * 0.5 + 0.5;
    return screenSpacePos.xy - prevScreenSpacePos.xy;
}

#endif
#endif
