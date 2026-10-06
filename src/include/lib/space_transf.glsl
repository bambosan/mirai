#ifndef SPACE_TRANSFORMS_INCLUDED
#define SPACE_TRANSFORMS_INCLUDED

vec3 projToView(vec3 projPos, mat4 invProj) {
    vec4 viewPos = invProj * vec4(projPos, 1.0);
    return viewPos.xyz / viewPos.w;
}

vec3 projToWorld(vec3 projPos, mat4 invViewProj) {
    vec4 worldPos = invViewProj * vec4(projPos, 1.0);
    return worldPos.xyz / worldPos.w;
}

vec3 viewToProj(vec3 viewPos, mat4 proj) {
    vec4 clipPos = proj * vec4(viewPos, 1.0);
    vec3 ndc = clipPos.xyz / clipPos.w;
    vec2 uv = ndc.xy * 0.5 + 0.5;
#if !TRANSPILE_TARGET__GLSL
    uv.y = 1.0 - uv.y;
#endif
    return vec3(uv, ndc.z);
}

#endif
