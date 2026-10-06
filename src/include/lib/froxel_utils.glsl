#ifndef FROXEL_UTILS_INCLUDED
#define FROXEL_UTILS_INCLUDED

float logToLinearDepth(float logDepth) {
    return (exp(4.0 * logDepth) - 1.0) / (exp(4.0) - 1.0);
}

float linearToLogDepth(float linearDepth) {
    return log((exp(4.0) - 1.0) * linearDepth + 1.0) / 4.0;
}

vec3 ndcToVolume(vec2 nearFar, vec3 ndc, mat4 invProj) {
    vec2 uv = ndc.xy * 0.5 + 0.5;
    vec4 view = invProj * vec4(ndc, 1.0);
    float viewDepth = (-view.z) / view.w;
    float wLinear = (viewDepth - nearFar.x) / (nearFar.y - nearFar.x);
    return vec3(uv, linearToLogDepth(wLinear));
}

vec3 volumeToNdc(vec2 nearFar, vec3 uvw, mat4 proj) {
    vec2 xy = uvw.xy * 2.0 - 1.0;
    float wLinear = logToLinearDepth(uvw.z);
    float viewDepth = -((1.0 - wLinear) * nearFar.x + wLinear * nearFar.y);
    vec4 ndcDepth = proj * vec4(0.0, 0.0, viewDepth, 1.0);
    float z = ndcDepth.z / ndcDepth.w;
    return vec3(xy, z);
}

vec3 worldToVolume(vec2 nearFar, vec3 world, mat4 viewProj, mat4 invProj) {
    vec4 proj = viewProj * vec4(world, 1.0);
    vec3 ndc = proj.xyz / proj.w;
    return ndcToVolume(nearFar, ndc, invProj);
}

vec3 volumeToWorld(vec2 nearFar, vec3 uvw, mat4 invViewProj, mat4 proj) {
    vec3 ndc = volumeToNdc(nearFar, uvw, proj);
    vec4 world = invViewProj * vec4(ndc, 1.0);
    return world.xyz / world.w;
}

vec4 sampleVolume(sampler2DArray volumeTex, vec3 uvw, float dslice) {
    float depth = uvw.z * dslice - 0.5;
    int slice = clamp(int(depth), 0, int(dslice) - 2);
    float ob = clamp(depth - float(slice), 0.0, 1.0);
    vec4 a = textureLod(volumeTex, vec3(uvw.xy, slice), 0.0);
    vec4 b = textureLod(volumeTex, vec3(uvw.xy, slice + 1), 0.0);
    return mix(a, b, ob);
}

#endif
