#ifndef BRDF_INCLUDED
#define BRDF_INCLUDED

#include "common.glsl"

// https://google.github.io/filament/main/filament.html

float dGGX(float NoH, float a) {
    float a2 = a * a;
    float f = (NoH * a2 - NoH) * NoH + 1.0;
    return a2 / (PI * f * f);
}

float vSmithGGXCorrelated(float NoV, float NoL, float a) {
    float a2 = a * a;
    float ggxl = NoV * sqrt((-NoL * a2 + NoL) * NoL + a2);
    float ggxv = NoL * sqrt((-NoV * a2 + NoV) * NoV + a2);
    return 0.5 / (ggxv + ggxl);
}

vec3 fSchlick(float u, vec3 f0) {
    return f0 + (vec3(1.0) - f0) * pow(1.0 - u, 5.0);
}

vec3 calcSpecular(vec3 normal, vec3 lightDir, vec3 viewDir, vec3 f0, float roughness) {
    vec3 halfDir = normalize(lightDir + viewDir);

    float NoV = abs(dot(normal, viewDir)) + EPSILON;
    float NoL = clamp(dot(normal, lightDir), 0.0, 1.0);
    float NoH = clamp(dot(normal, halfDir), 0.0, 1.0);
    float LoH = clamp(dot(lightDir, halfDir), 0.0, 1.0);

    float a = max(roughness * roughness, 0.0025);
    float d = dGGX(NoH, a);
    float v = vSmithGGXCorrelated(NoV, NoL, a);
    vec3 f = fSchlick(LoH, f0);

    return d * v * f * NoL * (1.0 - roughness);
}

#endif
