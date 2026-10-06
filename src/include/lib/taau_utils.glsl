#ifndef TAAU_UTILS_INCLUDED
#define TAAU_UTILS_INCLUDED

vec4 jitterVertexPosition(vec4 subPixelOffset, vec3 worldPos, mat4 view, mat4 proj) {
    mat4 offsetProj = proj;
#if TRANSPILE_TARGET__GLSL
    offsetProj[2].x += subPixelOffset.x;
    offsetProj[2].y -= subPixelOffset.y;
#else
    offsetProj[0].z += subPixelOffset.x;
    offsetProj[1].z -= subPixelOffset.y;
#endif
    return offsetProj * view * vec4(worldPos, 1.0);
}

vec2 calculateMotionVector(vec3 worldPos, vec3 prevWorldPos, mat4 viewProj, mat4 prevViewProj) {
    vec4 screenSpacePos = viewProj * vec4(worldPos, 1.0);
    screenSpacePos /= screenSpacePos.w;
    screenSpacePos = screenSpacePos * 0.5 + 0.5;
    vec4 prevScreenSpacePos = prevViewProj * vec4(prevWorldPos, 1.0);
    prevScreenSpacePos /= prevScreenSpacePos.w;
    prevScreenSpacePos = prevScreenSpacePos * 0.5 + 0.5;
    return screenSpacePos.xy - prevScreenSpacePos.xy;
}

#endif
