#ifndef CLOUDS_INCLUDED
#define CLOUDS_INCLUDED

// CLOUDS!
// https://www.guerrilla-games.com/read/the-real-time-volumetric-cloudscapes-of-horizon-zero-dawn
// https://www.guerrilla-games.com/read/nubis-realtime-volumetric-cloudscapes-in-a-nutshell
// https://media.contentapi.ea.com/content/dam/eacom/frostbite/files/s2016-pbs-frostbite-sky-clouds-new.pdf

#define CUMULUS_HEIGHT 180.0
#define CUMULUS_THICKNESS 200.0
#define CUMULUS_VOLUME_MAX_STEP_COUNTS 200
#define CUMULUS_VOLUME_STEP_SPACE 10.0
#define CIRRUS_HEIGHT (CUMULUS_HEIGHT + CUMULUS_THICKNESS + 200.0)

//terrain
#define CUMULUS_SHADOW_CONTRIBUTION 0.5

#define CUMULUS_SHADOW_MAX_STEPS 24
#define CUMULUS_SHADOW_MIN_STEPS 6
#define CUMULUS_SHADOW_STEP_SPACE 20.0
#define CUMULUS_SHADOW_MAX_PATH 1000.0

#include "common.glsl"
#include "noises.glsl"
#include "atmosphere.glsl"

struct CloudSetup {
    float tMin;
    float tMax;
    int stepCounts;
    bool isValidCloud;
};

CloudSetup calcCloudSetup(float direction, float camAltitude) {
    CloudSetup setup;
    setup.tMin = 0.0;
    setup.tMax = 1e6;
    setup.stepCounts = CUMULUS_VOLUME_MAX_STEP_COUNTS;
    setup.isValidCloud = true;

    float cloudMaxY = CUMULUS_HEIGHT + CUMULUS_THICKNESS;
    float tBottomPlane = (CUMULUS_HEIGHT - camAltitude) / direction;
    float tTopPlane = (cloudMaxY - camAltitude) / direction;

    if (camAltitude > cloudMaxY) {
        //camera is above the clouds
        if (direction > 0.0) {
            setup.isValidCloud = false;
            return setup;
        }
        setup.tMin = tTopPlane;
        setup.tMax = tBottomPlane;
    } else if (camAltitude < CUMULUS_HEIGHT) {
        //camera is below the clouds
        if (direction < 0.0) {
            setup.isValidCloud = false;
            return setup;
        }
        setup.tMin = tBottomPlane;
        setup.tMax = tTopPlane;
    } else {
        //camera inside cloud layer
        setup.tMin = 0.0;
        setup.tMax = direction > 0.0 ? tTopPlane : tBottomPlane;
    }

    float raySpan = (setup.tMax - setup.tMin) / CUMULUS_VOLUME_STEP_SPACE;
    setup.stepCounts = min(setup.stepCounts, int(raySpan));

    return setup;
}

float calcCumulusModel(vec3 pos, float time, float rain) {
    vec2 windDir = vec2(0.0, time);
    vec2 basePos = (pos.xz + windDir) * 0.025;

    float base = linearstep(max(0.5, rain * 0.8), 1.0, worley2d(basePos)) * 0.5;

    float heightFraction = clamp((pos.y - CUMULUS_HEIGHT) / CUMULUS_THICKNESS, 0.0, 1.0);
    base = linearstep(exp(-(1.0 - heightFraction) * 10.0), 1.0, base); //top sculpting
    base = linearstep(exp(-heightFraction * 25.0), 1.0, base); //bottom sculpting

    //worley sculpting for billow shape
    float wsculpting = linearstep(0.0, 1.0 - rain * 0.4, worley3d(pos * 0.15 + windDir.xxy * 0.01));
    base = smoothstep(wsculpting * heightFraction, 1.0, base);
    return base;
}

float calcDirectScattering(
    vec3 samplePos,
    vec3 lightDir,
    float extinction,
    float transmittance,
    float costh,
    float time,
    float rain
) {
    float shadow = 0.0;
    float stepSpace = CUMULUS_THICKNESS / max(lightDir.y, 0.01) * 0.25;
    stepSpace = min(stepSpace, CUMULUS_THICKNESS);

    for (int i = 0; i < 4; i++) {
        samplePos += lightDir * stepSpace * 0.1;
        shadow += calcCumulusModel(samplePos, time, rain);
    }

    float lighting = 0.0;
    float modulator = max(lightDir.y, 0.0);
    float shadowM = modulator * 0.3 + 0.7;
    float g = 0.7; //anisotropy factor
    float b = 1.0 + modulator; //brightness
    float a = 1.0; //shadow

    for (int j = 0; j < 4; j++) {
        float dphase = phase(costh, g, 1.0);
        lighting += b * dphase * exp(-shadow * stepSpace * a);
        a *= shadowM * 0.35;
        g *= 0.15;
        b *= 0.5;
    }

    float powder = 1.0 - exp(-extinction * CUMULUS_VOLUME_STEP_SPACE * 10.0);
    powder = max(powder, 1.0 - transmittance);
    lighting *= mix(powder + pow(powder, 5.0), 1.0, costh * 0.5 + 0.5);

    return lighting;
}

vec4 calcCloud(
    vec3 worldDir,
    vec3 lightDir,
    float worldDist,
    float dither,
    float time,
    float rain,
    bool isTerrain,
    CloudSetup setup
) {
    if (!setup.isValidCloud) return vec4(0.0, 0.0, 0.0, 1.0);

    vec3 rayOrigin = -WorldOrigin.xyz;
    vec3 rayDir = worldDir;

    float costh = dot(worldDir, lightDir);

    vec2 lighting = vec2(0.0);
    float wdepth = 0.0; //weighted depth, used for atmosphere contribution
    float tweight = 0.0;
    float transmittance = 1.0;

    if (isTerrain) setup.tMax = min(setup.tMax, worldDist);

    for (int i = 0; i < setup.stepCounts; i++) {
        vec3 samplePos = rayOrigin + rayDir * (setup.tMin + dither * CUMULUS_VOLUME_STEP_SPACE);
        float extinction = calcCumulusModel(samplePos, time, rain);

        if (extinction > 0.0) {
            float dscattering = calcDirectScattering(samplePos, lightDir, extinction,
                transmittance, costh, time, rain);
            float iscattering = clamp((samplePos.y - CUMULUS_HEIGHT) / CUMULUS_THICKNESS, 0.0, 1.0);
            vec2 tscattering = vec2(dscattering, iscattering) * extinction;

            float stepTransmittance = exp(-extinction * CUMULUS_VOLUME_STEP_SPACE);

            //https://www.shadertoy.com/view/XlBSRz
            vec2 scatterInt = (tscattering - tscattering * stepTransmittance)
                / max(extinction, EPSILON);

            lighting += transmittance * scatterInt;
            wdepth += transmittance * setup.tMin;
            tweight += transmittance;
            transmittance *= stepTransmittance;
        }

        if (transmittance < EPSILON) break;

        setup.tMin += CUMULUS_VOLUME_STEP_SPACE;
        if (setup.tMin > setup.tMax) break;
    }

    wdepth /= max(tweight, EPSILON);
    return vec4(lighting, wdepth, transmittance);
}

void applyCumulusClouds(
    inout vec3 outColor,
    vec3 absorbColor,
    vec3 scatterColor,
    vec3 worldDir,
    vec3 lightDir,
    vec3 sunDir,
    vec3 moonDir,
    float rain,
    float worldDist,
    float dither,
    float time,
    bool isTerrain
) {
    CloudSetup cloudSetup = calcCloudSetup(worldDir.y, -WorldOrigin.y);
    vec4 clouds = calcCloud(
        worldDir,
        lightDir,
        worldDist,
        dither,
        time,
        rain,
        isTerrain,
        cloudSetup
    );

    vec3 cRayleigh, cMie, cOzone;
    atmConstant(rain, cRayleigh, cMie, cOzone);

    float altModulator = smoothstep(CUMULUS_HEIGHT + CUMULUS_THICKNESS, CUMULUS_HEIGHT, -WorldOrigin.y);
    AtmosphereParams sunAtmParams = AtmosphereParams(
        cRayleigh,
        cMie,
        cOzone,
        worldDir,
        sunDir,
        clouds.b,
        altModulator * 20.0 + 10.0,
        1.0,
        rain
    );

    AtmosphereParams moonAtmParams = sunAtmParams;
    moonAtmParams.lightDir = moonDir;
    moonAtmParams.occlusion = 0.0;

    vec4 transmittance;
    vec3 atmContrib = calcAtmosphere(sunAtmParams, transmittance) * SUN_RADIANCE_MULTIPLIER;
    vec4 _unused;
    atmContrib += luminance(calcAtmosphere(moonAtmParams, _unused))
        * MOON_RADIANCE_MULTIPLIER;

    clouds.rg *= mix(vec2(0.2, 0.0), vec2(1.0), smoothstep(0.0, 0.1, sunDir.y));

    vec3 cloudsColor = (clouds.r * absorbColor * max(0.5, rain) + clouds.g * scatterColor * 0.5)
        * saturation(transmittance.rgb, smoothstep(0.2, 0.0, moonDir.y));
    cloudsColor += atmContrib * (1.0 - clouds.a);
    outColor = clouds.a * outColor + cloudsColor;
}

float calcCloudTransmittanceOnly(
    vec3 worldDir,
    float worldDist,
    float dither,
    float time,
    float rain,
    bool isTerrain,
    CloudSetup setup
) {
    if (!setup.isValidCloud) return 1.0;

    vec3 rayOrigin = -WorldOrigin.xyz;
    vec3 rayDir = worldDir;

    if (isTerrain) setup.tMax = min(setup.tMax, worldDist);

    float transmittance = 1.0;

    for (int i = 0; i < setup.stepCounts; i++) {
        vec3 samplePos = rayOrigin + rayDir * (setup.tMin + dither * CUMULUS_VOLUME_STEP_SPACE);
        float extinction = calcCumulusModel(samplePos, time, rain);
        if (extinction > 0.0) transmittance *= exp(-extinction * CUMULUS_VOLUME_STEP_SPACE);
        if (transmittance < EPSILON) break;

        setup.tMin += CUMULUS_VOLUME_STEP_SPACE;
        if (setup.tMin > setup.tMax) break;
    }

    return transmittance;
}

float calcCloudShadow(vec3 position, vec3 lightDir, float hardness, float time, float rain) {
    float cloudMaxY = CUMULUS_HEIGHT + CUMULUS_THICKNESS;
    if (lightDir.y <= 0.0 || position.y >= cloudMaxY) return 1.0;

    float tMin = max(CUMULUS_HEIGHT - position.y, 0.0) / lightDir.y;
    float tMax = min((cloudMaxY - position.y) / lightDir.y, tMin + CUMULUS_SHADOW_MAX_PATH);
    float pathLength = tMax - tMin;
    if (pathLength <= 0.0) return 1.0;

    float stepLen = pathLength / clamp(
        ceil(pathLength / CUMULUS_SHADOW_STEP_SPACE),
        float(CUMULUS_SHADOW_MIN_STEPS),
        float(CUMULUS_SHADOW_MAX_STEPS)
    );
    float transmittance = 1.0;

    for (int i = 0; i < CUMULUS_SHADOW_MAX_STEPS; i++) {
        vec3 samplePos = position + lightDir * tMin;
        float extinction = calcCumulusModel(samplePos, time, rain) * stepLen;
        if (extinction > 0.0) transmittance *= exp(-extinction * hardness);
        if (transmittance < EPSILON) break;

        tMin += stepLen;
        if (tMin > tMax) break;
    }

    return transmittance;
}

float calcCirrusModel(vec2 pos, float time) {
    float tdensity = 0.0;
    float amplitude = 1.0;

    pos.x *= 0.25;

    for (int i = 0; i < 4; i++) {
        pos.y += time * 0.01;
        float dens = perlinNoise(pos) * amplitude;
        tdensity += dens;
        pos *= 2.5;
        pos.x += pos.x * (dens * 0.5 + 0.5);
        amplitude *= 0.5;
    }

    return smoothstep(0.45, 1.0, tdensity * 0.533333);
}

void applyCirrusClouds(
    inout vec3 outColor,
    vec3 worldDir,
    vec3 rayOrigin,
    vec3 sunDir,
    vec3 moonDir,
    vec3 absorbColor,
    vec3 scatterColor,
    float rain,
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
    float extinction = calcCirrusModel(samplePos.xz * 0.01, time) * distFade * altFade;

    float transmittance = exp(-extinction);
    float sphase = phase(dot(worldDir, sunDir), 0.1, 1.0);
    float mphase = phase(dot(worldDir, moonDir), 0.5, 1.0);

    vec3 scatterCol = mix(absorbColor * rain * 0.25 * mphase,
        (absorbColor * 0.5 + scatterColor * 4.0) * max(rain, 0.5) * sphase,
        smoothstep(0.0, 0.1, sunDir.y));
    outColor = outColor * transmittance + scatterCol * (1.0 - transmittance);
}

#endif
