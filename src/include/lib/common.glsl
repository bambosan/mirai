#ifndef COMMON_INCLUDED
#define COMMON_INCLUDED

#define EPSILON 0.0001
#define INF 1e17

#define PI 3.14159265359
#define HALF_PI 1.57079632679
#define INV_PI 0.31830988618

#define LUMA_REC709 vec3(0.2126, 0.7152, 0.0722)
#define MIDDLE_GRAY 0.18

#define EXPOSURE_MULTIPLIER 100.0
#define SKY_AMBIENT_MULTIPLIER 2.0
#define BLOCK_AMBIENT_MULTIPLIER 0.01
#define EMISSIVE_MATERIAL_INTENSITY 0.1
#define BORDER_FOG_INTENSITY 0.1
#define SUN_RADIANCE_MULTIPLIER 1.0
#define MOON_RADIANCE_MULTIPLIER 0.001

#define DEFAULT_F0 vec3(0.04)
#define WATER_F0 vec3(0.02)
#define GLASS_F0 vec3(0.08)

#define WATER_EXTINCTION_COEFFICIENTS vec3(0.5, 0.35, 0.3)

float linearstep(float edge0, float edge1, float x) {
    return clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
}

float luminance(vec3 color) {
    return dot(color, LUMA_REC709);
}

float colorAvg(vec3 color) {
    return (color.r + color.g + color.b) / 3.0;
}

vec3 saturation(vec3 color, float val) {
	float lum = luminance(color);
    return mix(vec3(lum), color, val);
}

vec3 preExposeLighting(vec3 color, float luminance) {
    return color * (MIDDLE_GRAY / luminance + EPSILON);
}

vec3 unExposeLighting(vec3 color, float luminance) {
    return color / (MIDDLE_GRAY / luminance + EPSILON);
}

float sampleDepth(sampler2D depthtex, vec2 uv) {
#if TRANSPILE_TARGET__GLSL
    return textureLod(depthtex, uv, 0.0).r * 2.0 - 1.0;
#else
    return textureLod(depthtex, uv, 0.0).r;
#endif
}

// https://iquilezles.org/articles/intersectors/
vec2 sphereIntersect(vec3 rayStart, vec3 rayDir, vec3 sphereCenter, float sphereRadius) {
    vec3 oc = rayStart - sphereCenter;
    float b = dot(oc, rayDir);
    float c = dot(oc, oc) - sphereRadius * sphereRadius;
    float h = b * b - c;
    if (h < 0.0) {
        return vec2(-1.0);
    } else {
        h = sqrt(h);
        return vec2(-b - h, -b + h);
    }
}

// https://research.nvidia.com/labs/rtr/approximate-mie/assets/draine.hlsl
float phase(float u, float g, float a) {
    return ((1.0 - g * g) * (1.0 + a * u * u))
        / (4.0 * (1.0 + (a * (1.0 + 2.0 * g * g)) / 3.0)
            * PI * pow(1.0 + g * g - 2.0 * g * u, 1.5));
}

vec3 fromLinear(vec3 color) {
    return mix(
        12.92 * color,
        pow(color, vec3(1.0 / 2.4)) * 1.055 - 0.055,
        step(0.0031308, color)
    );
}

vec3 toLinear(vec3 color){
    return mix(
        color * 0.07739938080495356,
        pow((color + 0.055) * 0.9478672985781990521327, vec3(2.4)),
        step(0.040449936, color)
    );
}

float diffuseLambert(vec3 n, vec3 l) {
    return clamp(dot(n, l), 0.0, 1.0) / PI;
}

float diffuseWrap(vec3 n, vec3 l, float w) {
    return clamp((dot(n, l) + w) / (1.0 + w), 0.0, 1.0) / PI;
}

uint pack2x8(vec2 values) {
    uvec2 bytes = uvec2(clamp(values, 0.0, 1.0) * 255.0) & 0xFFu;
    return (bytes.x << 8) | bytes.y;
}

bool isOverworld(float val) { return val > 0.0 && val < 0.2; }
bool isNetherworld(float val) { return val > 0.1 && val < 0.3; }
bool isEndworld(float val) { return val > 0.2 && val < 0.4; }

#endif
