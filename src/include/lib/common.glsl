#ifndef COMMON_INCLUDE
#define COMMON_INCLUDE

#define EPSILON 0.0001
#define PI 3.14159265358979
#define HALF_PI 1.57079632679489

#define LUMA_REC709 vec3(0.2126, 0.7152, 0.0722)
#define MIDDLE_GRAY 0.18

#define BLOCK_LIGHT_COLOR vec3(1.0, 0.7, 0.5)
#define BLOCK_LIGHT_INTENSITY 15.0
#define SKY_LIGHT_INTENSITY 1.0
#define EMISSIVE_MATERIAL_INTENSITY 25.0
#define MIN_AMBIENT_LIGHT 0.01

#define SUN_MAX_ILLUMINANCE 100.0
#define MOON_MAX_ILLUMINANCE 0.25

#define WATER_EXTINCTION_COEFFICIENTS vec3(0.5, 0.35, 0.3)

float luminance(vec3 color) {
    return dot(color, LUMA_REC709);
}

float linearstep(float edge0, float edge1, float x) {
    return clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
}

vec3 saturation(vec3 color, float val) {
    return mix(vec3_splat(luminance(color)), color, val);
}

vec3 preExposeLighting(vec3 color, float luminance) {
    return color * (MIDDLE_GRAY / luminance + EPSILON);
}

vec3 unExposeLighting(vec3 color, float luminance) {
    return color / (MIDDLE_GRAY / luminance + EPSILON);
}

float calculateFogIntensityVanilla(float cameraDepth, float maxDistance, float fogStart, float fogEnd) {
    float dist = cameraDepth / maxDistance;
    return saturate((dist - fogStart) / (fogEnd - fogStart));
}

float calculateFogIntensityFaded(float cameraDepth, float maxDistance, float fogStart, float fogEndMinusStartReciprocal, float fogAlpha) {
    float dist = cameraDepth / maxDistance;
    dist += fogAlpha;
    return saturate((dist - fogStart) * fogEndMinusStartReciprocal);
}

float sampleDepth(highp sampler2D depthtex, vec2 uv) {
#if BGFX_SHADER_LANGUAGE_GLSL
    return texture2DLod(depthtex, uv, 0.0).r * 2.0 - 1.0;
#else
    return texture2DLod(depthtex, uv, 0.0).r;
#endif
}

//https://github.com/bWFuanVzYWth/OriginShader/blob/main/OriginShader/shaders/glsl/shaderfunction.lin
float ux2l(float l) { return 1.0 / (l * l); }
float uv1x2lig(float uv1x) {
    uv1x *= 0.75;
    float l = clamp((14.0 / 16.0) - uv1x, 0.0, 1.0) * 16.0 + 0.5;
    return max(0.0, ux2l(l) - ux2l(15.0) * (1.0 - uv1x));
}

//https://www.shadertoy.com/view/4djSRW
float hash12(vec2 p) {
	vec3 p3  = fract(p.xyx * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise2d(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
	
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
	
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, float time) {
    float s = 0.0;
    float a = 0.3;
	float wind = time * 0.1;
    
    for (int i = 0; i < 4; i++) {
        s += noise2d(p + wind) * a;
        p *= 2.5;
        a *= 0.5;
    }
	
    return smoothstep(0.25, 1.0, s);
}

vec3 calcClouds(vec3 nWorldPos, vec3 sunDir, vec3 moonDir, vec3 scatterColor, vec3 absorbColor, vec3 sky, float time) {
    vec2 cloudpos = nWorldPos.xz / max(nWorldPos.y, EPSILON);
    float cm = fbm(cloudpos, time);

    float sunCost = max(distance(nWorldPos, sunDir), 0.0);
    float moonCost = max(distance(nWorldPos, moonDir), 0.0);

    vec3 cloudCol = scatterColor;
    cloudCol += absorbColor * exp(-sunCost * 2.0) * smoothstep(0.0, 0.2, sunDir.y);
    cloudCol += absorbColor * exp(-moonCost * 3.0) * smoothstep(0.0, 0.2, moonDir.y);

    sky = mix(sky, cloudCol, cm * smoothstep(0.0, 0.25, nWorldPos.y));
    return sky;
}

#endif
