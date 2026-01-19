#ifndef BSDF_INCLUDE
#define BSDF_INCLUDE

float D_GGX_TrowbridgeReitz(float NoH, float a) {
    float a2 = a * a;
    float f = (a2 - 1.0) * NoH * NoH + 1.0;
    return a2 / (f * f * PI);
}

float V_SmithGGXCorrelated(float NoV, float NoL, float a) {
    float a2 = a * a;
    float GGXV = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
    float GGXL = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
    return 0.5 / max((GGXV + GGXL), EPSILON);
}

vec3 F_Schlick(float u, vec3 f0) {
    float f = pow(1.0 - u, 5.0);
    return f + f0 * (1.0 - f);
}

float wrappedDiffuse(vec3 n, vec3 l, float w) {
    return max((dot(n, l) + w) / (1.0 + w), 0.0);
}

vec3 BSDF(vec3 n, vec3 l, vec3 v, vec3 f0, vec3 albedo, vec2 shadow, float metalness, float roughness, float subsurface, float sssFallof) {
    vec3 h = normalize(l + v);
    float NoV = saturate(dot(n, v));
    float NoL = saturate(dot(n, l));
    float NoH = saturate(dot(n, h));
    float LoH = saturate(dot(l, h));

    float a = roughness * roughness;
    float D = D_GGX_TrowbridgeReitz(NoH, a);
    vec3 F = F_Schlick(LoH, f0);
    float V = V_SmithGGXCorrelated(NoV, NoL, a);
    vec3 specular = (D * V) * F * NoL;

    albedo = (1.0 - metalness) * albedo;
    vec3 diffuse = mix(NoL, wrappedDiffuse(n, l, sssFallof), subsurface) * (1.0 - F) * albedo / PI;
    vec3 transmittedDiffuse = subsurface * wrappedDiffuse(-n, l, sssFallof) * (1.0 - F) * albedo / PI;

    return diffuse * shadow.r + transmittedDiffuse * shadow.g + specular * shadow.r;
}

vec3 BRDFSpecular(vec3 n, vec3 l, vec3 v, vec3 f0, float shadow, float metalness, float roughness) {
    vec3 h = normalize(l + v);
    float NoV = saturate(dot(n, v));
    float NoL = saturate(dot(n, l));
    float NoH = saturate(dot(n, h));
    float LoH = saturate(dot(l, h));

    float a = roughness * roughness;
    float D = D_GGX_TrowbridgeReitz(NoH, a);
    vec3 F = F_Schlick(LoH, f0);
    float V = V_SmithGGXCorrelated(NoV, NoL, a);

    return (D * V) * F * NoL * shadow;
}

#endif
