#ifndef CLOUDS_INCLUDED
#define CLOUDS_INCLUDED

#define CIRRUS_HEIGHT 580.0

#include "common.glsl"
#include "noises.glsl"

float calcCirrusModel(vec2 pos, float time) {
    float tdensity = 0.0;
    float amplitude = 0.2;

    pos.x += sin(pos.y * 2.0 + time * 0.005) * 0.1;

    for (int i = 0; i < 4; i++) {
        pos.y += time * 0.01;
        float dens = valueNoise(pos) * amplitude;
        tdensity += dens;
        pos *= 2.0;
        pos.x += pos.x * 0.5;
        amplitude *= 0.5;
    }

    return clamp(tdensity - 0.15, 0.0, 1.0);
}

void applyCirrusClouds(
    inout vec3 outColor,
    vec3 worldDir,
    vec3 rayOrigin,
    vec3 lightDir,
    vec3 cloudColor,
    float time,
    bool isTerrain
) {
    float tPlane = (CIRRUS_HEIGHT - rayOrigin.y) / worldDir.y;
    if (isTerrain || tPlane < 0.0
        || (worldDir.y < 0.0 && rayOrigin.y < CIRRUS_HEIGHT)
        || (worldDir.y > 0.0 && rayOrigin.y > CIRRUS_HEIGHT)
    ) return;

    vec3 samplePos = rayOrigin + worldDir * tPlane;
    float distFade = smoothstep(0.0, 0.2, worldDir.y);
    float altFade = smoothstep(0.0, 180.0, CIRRUS_HEIGHT - rayOrigin.y);
    float extinction = calcCirrusModel(samplePos.xz * 0.0025, time) * distFade * altFade;

    float transmittance = exp(-extinction);
    float costh = dot(worldDir, lightDir);
    float phase = phase(costh, 0.1, 1.0);
    outColor = outColor * transmittance + cloudColor * phase * (1.0 - transmittance);
}

#endif
