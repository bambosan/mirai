#ifndef FROXEL_UTIL_INCLUDE
#define FROXEL_UTIL_INCLUDE

uniform highp vec4 VolumeDimensions;
uniform highp vec4 VolumeNearFar;
uniform highp vec4 VolumeScatteringEnabledAndPointLightVolumetricsEnabled;

float logToLinearDepth(float logDepth) {
    return (exp(4.0 * logDepth) - 1.0) / (exp(4.0) - 1.0);
}

float linearToLogDepth(float linearDepth) {
    return log((exp(4.0) - 1.0) * linearDepth + 1.0) / 4.0;
}

vec3 ndcToVolume(vec3 ndc) {
    vec2 uv = ndc.xy * 0.5 + 0.5;
    vec4 view = mul(u_invProj, vec4(ndc, 1.0));
    float viewDepth = -view.z / view.w;
    float wLinear = (viewDepth - VolumeNearFar.x) / (VolumeNearFar.y - VolumeNearFar.x);
    return vec3(uv, linearToLogDepth(wLinear));
}

vec3 volumeToNdc(vec3 uvw) {
    vec2 xy = uvw.xy * 2.0 - 1.0;
    float wLinear = logToLinearDepth(uvw.z);
    float viewDepth = -((1.0 - wLinear) * VolumeNearFar.x + wLinear * VolumeNearFar.y);
    vec4 ndcDepth = mul(u_proj, vec4(0.0, 0.0, viewDepth, 1.0));
    float z = ndcDepth.z / ndcDepth.w;
    return vec3(xy, z);
}

vec3 worldToVolume(vec3 world) {
    vec4 proj = mul(u_viewProj, vec4(world, 1.0));
    vec3 ndc = proj.xyz / proj.w;
    return ndcToVolume(ndc);
}

vec3 volumeToWorld(vec3 uvw) {
    vec3 ndc = volumeToNdc(uvw);
    vec4 world = mul(u_invViewProj, vec4(ndc, 1.0));
    return world.xyz / world.w;
}

vec4 sampleVolume(highp sampler2DArray volume, vec3 uvw) {
    float depth = uvw.z * VolumeDimensions.z - 0.5;
    int slice = clamp(int(depth), 0, int(VolumeDimensions.z) - 2);
    float offsets = saturate(depth - float(slice));
    vec4 a = texture2DArrayLod(volume, vec3(uvw.xy, slice), 0.0);
    vec4 b = texture2DArrayLod(volume, vec3(uvw.xy, slice + 1), 0.0);
    return mix(a, b, offsets);
}

#endif
