#ifndef GBUFFER_UTILS_INCLUDED
#define GBUFFER_UTILS_INCLUDED

vec2 unpackTexcoord0(vec2 packed) {
    uvec2 q = uvec2(roundEven(packed * 65535.0));

    vec2 decoded = vec2((q.x & 0x7FFFu) << 1, (q.y & 0x7FFFu) << 1) / 65535.0;
    decoded.x += (float((q.x & 0x8000u) >> 15) * 2.0 - 1.0) / 32768.0;
    decoded.y += (float((q.y & 0x8000u) >> 15) * 2.0 - 1.0) / 32768.0;
    return decoded;
}

struct Texcoord1Data {
    vec3 lightData;
    vec2 ditheringAndMaskTinting;
    vec2 lightmapUV;
};

Texcoord1Data unpackTexcoord1(vec2 packed) {
    uvec2 q = uvec2(roundEven(packed * 65535.0));

    uvec2 high = (q >> 8) & 0xFFu;
    uvec2 low = q & 0xFFu;
    uvec2 even = high & 0xFEu;

    return Texcoord1Data(
        vec3(even.x, low.x, even.y) / 255.0,
        vec2(notEqual(high & 1u, uvec2(0))),
        vec2((q.y >> 4) & 0xFu, q.y & 0xFu) / 15.0
    );
}

vec3 swLightColor(vec3 lightColor, float blockLM) {
    if ((lightColor.x + lightColor.y + lightColor.z) < 0.0 && blockLM > 0.0)
        return vec3(clamp(blockLM * blockLM, 0.0, 1.0));
    return lightColor;
}

uvec2 packLight(vec3 lightColor) {
    vec3 scaled = lightColor / 6.0;
    float maxComponent = ceil(clamp(max(max(scaled.r, scaled.g), scaled.b), 0.0, 1.0)
        * 255.0) / 255.0;
    uvec4 q = uvec4(clamp(vec4(scaled / vec3(maxComponent), maxComponent), 0.0, 1.0) * 255.0);
    uvec2 lo = q.xy & 0xFFu;
    uvec2 hi = q.zw & 0xFFu;
    return uvec2((lo.x << 8u) | lo.y, (hi.x << 8u) | hi.y);
}

mat4 instanceMatrix(vec4 data1, vec4 data2, vec4 data3) {
    return mat4(
        vec4(data1.x, data2.x, data3.x, 0.0),
        vec4(data1.y, data2.y, data3.y, 0.0),
        vec4(data1.z, data2.z, data3.z, 0.0),
        vec4(data1.w, data2.w, data3.w, 1.0)
    );
}

vec3 applyBillboard(vec3 center, vec3 billboardParams) {
    vec3 viewDir = normalize(-center);
    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), viewDir));
    vec3 up = cross(viewDir, right);
    return center - (up * (billboardParams.z - 0.5) + right * (billboardParams.x - 0.5));
}

#endif
