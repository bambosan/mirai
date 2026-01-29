#ifndef BSDF_INCLUDE
#define BSDF_INCLUDE

// https://google.github.io/filament/main/filament.html

float D_GGX_TrowbridgeReitz(float NoH, float a) {
    float a2 = a * a;
    float f = max((a2 - 1.0) * NoH * NoH + 1.0, EPSILON);
    return a2 / (f * f * PI);
}

float V_SmithGGXCorrelated(float NoV, float NoL, float a) {
    float a2 = a * a;
    float GGXV = NoL * sqrt(max(NoV * NoV * (1.0 - a2) + a2, 0.0));
    float GGXL = NoV * sqrt(max(NoL * NoL * (1.0 - a2) + a2, 0.0));
    return 0.5 / max(GGXV + GGXL, EPSILON);
}

vec3 F_Schlick(float u, vec3 f0) {
    return f0 + (vec3_splat(1.0) - f0) * pow(clamp(1.0 - u, 0.0, 1.0), 5.0);
}

float wrappedDiffuse(vec3 n, vec3 l, float w) {
    return max((dot(n, l) + w) / ((1.0 + w) * (1.0 + w)), 0.0);
}

vec3 BSDF(vec3 n, vec3 l, vec3 v, vec3 f0, vec3 albedo, vec2 shadow, float metalness, float roughness, float subsurface) {
    vec3 h = normalize(l + v);
    
    float NoV = saturate(dot(n, v));
    float NoL = saturate(dot(n, l));
    float NoH = saturate(dot(n, h));
    float LoH = saturate(dot(l, h));

    float a = max(roughness * roughness, 0.0025);
    float D = D_GGX_TrowbridgeReitz(NoH, a);
    float V = V_SmithGGXCorrelated(NoV, NoL, a);
    vec3 F = F_Schlick(LoH, f0);
    vec3 specular = (D * V) * F * NoL;

    albedo = (1.0 - metalness) * albedo;
    
    vec3 noSpec = max(vec3_splat(0.0), vec3_splat(1.0) - F);
    vec3 diffuse = mix(NoL, wrappedDiffuse(n, l, 0.5), subsurface) * noSpec * albedo / PI;
    vec3 transmittedDiffuse = subsurface * wrappedDiffuse(-n, l, 0.5) * noSpec * albedo / PI;

    return diffuse * shadow.r + transmittedDiffuse * shadow.g + specular * shadow.r;
}

vec3 BRDFSpecular(vec3 n, vec3 l, vec3 v, vec3 f0, float shadow, float roughness) {
    vec3 h = normalize(l + v);
    
    float NoV = saturate(dot(n, v));
    float NoL = saturate(dot(n, l));
    float NoH = saturate(dot(n, h));
    float LoH = saturate(dot(l, h));

    float a = max(roughness * roughness, 0.0025);
    float D = D_GGX_TrowbridgeReitz(NoH, a);
    float V = V_SmithGGXCorrelated(NoV, NoL, a);
    vec3 F = F_Schlick(LoH, f0);

    vec3 specular = (D * V) * F * NoL;
    
    return specular * shadow;
}

#endif
