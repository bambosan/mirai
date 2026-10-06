#ifndef ATMOSPHERE_INCLUDED
#define ATMOSPHERE_INCLUDED

#include "common.glsl"

// Fast atmosphere
// https://www.shadertoy.com/view/4XffzH

#define AERIAL_SCALE 1.0
#define ATMOSPHERE_HEIGHT 100000.0
#define ATMOSPHERE_DENSITY 1.0
#define PLANET_RADIUS 6371000.0
#define PLANET_CENTER vec3(0, -PLANET_RADIUS, 0)
#define RAYLEIGH_MAX_LUM 2.5
#define MIE_MAX_LUM 0.5
#define M_EXPOSURE 0.25
#define M_FAKE_MS 0.3
#define M_AERIAL 2.5
#define M_LIGHT_TRANSMITTANCE 1e6
#define M_DENSITY_HEIGHT_MOD 1e-12
#define M_DENSITY_CAM_MOD 10.0
#define M_OZONE 5.0

#define CAM_ALTITUDE 100.0

struct AtmosphereParams {
    vec3 cRayleigh;
    vec3 cMie;
    vec3 cOzone;
    vec3 rayDir;
    vec3 lightDir;
    float rayLength;
    float aerial;
    float occlusion;
    float rain;
};

struct AtmosphericScattering {
    float opticalDepth;
    float densityR;
    float densityM;
    vec3 lightDir;
    vec3 lightColor;
    vec3 R;
    vec3 M;
    vec3 scattering;
};

vec3 calcLightTransmittance(
    vec3 lightDir,
    vec3 cRayleigh,
    vec3 cMie,
    vec3 cOzone,
    float multiplier
) {
    float lightExtinctionAmount = exp(-(clamp(lightDir.y + 0.05, 0.0, 1.0) * 40.0))
        + exp(-(clamp(lightDir.y + 0.3, 0.0, 1.0) * 5.0)) * 0.4
        + pow(clamp(1.0 - lightDir.y, 0.0, 1.0), 2.0) * 0.02;
    return exp(-(cRayleigh + cMie + cOzone)
        * lightExtinctionAmount
        * ATMOSPHERE_DENSITY
        * multiplier
        * M_LIGHT_TRANSMITTANCE);
}

AtmosphericScattering calcAtmosphereScattering(AtmosphereParams params, vec2 t1, vec2 t2) {
    AtmosphericScattering atm;

    t2.y -= max(0.0, t2.x);
    atm.opticalDepth = t1.x > 0.0 ? min(t1.x, t2.y) * 50.0 : t2.y;
    atm.opticalDepth = min(params.rayLength, atm.opticalDepth);
    atm.opticalDepth = min(atm.opticalDepth
        * params.aerial * M_AERIAL * AERIAL_SCALE, t2.y);

    float hbias = 1.0 - 1.0 / (2.0 + t2.y * t2.y * M_DENSITY_HEIGHT_MOD);
    hbias = pow(hbias, 1.0 + CAM_ALTITUDE / ATMOSPHERE_HEIGHT * M_DENSITY_CAM_MOD);
    atm.densityR = hbias * hbias * ATMOSPHERE_DENSITY;
    atm.densityM = pow(hbias, 5.0) * ATMOSPHERE_DENSITY;

    float ly = clamp(params.lightDir.y
        + clamp(-params.lightDir.y + 0.02, 0.0, 1.0)
        * clamp(params.lightDir.y + 0.7, 0.0, 1.0), -1.0, 1.0);
    atm.lightDir = vec3(params.lightDir.x, ly, params.lightDir.z);
    atm.lightColor = calcLightTransmittance(
        atm.lightDir,
        params.cRayleigh,
        params.cMie,
        params.cOzone,
        hbias
    );
    atm.R = (1.0 - exp(-atm.opticalDepth
        * atm.densityR
        * params.cRayleigh / RAYLEIGH_MAX_LUM)) * RAYLEIGH_MAX_LUM;
    atm.M = (1.0 - exp(-atm.opticalDepth
        * atm.densityM
        * params.cMie / MIE_MAX_LUM)) * MIE_MAX_LUM;

    float costh = dot(params.rayDir, params.lightDir);
    float phaseR = phase(costh, 0.0, 1.0);
    float phaseM = phase(costh, 0.8, 0.0);

    float desaturate = smoothstep(0.0, 0.1, params.lightDir.y) * 0.75 + 0.25;
    vec3 rayleigh = (phaseR * params.occlusion + phaseR * M_FAKE_MS)
        * saturation(atm.lightColor, desaturate);
    vec3 mie = (phaseM * params.occlusion + phaseR * M_FAKE_MS) * atm.lightColor;
    atm.scattering = mie * atm.M + rayleigh * atm.R;

    return atm;
}

vec3 calcAtmosphere(AtmosphereParams params, out vec4 transmittance) {
    vec2 t1 = sphereIntersect(
        vec3(0.0, CAM_ALTITUDE, 0.0),
        params.rayDir,
        PLANET_CENTER,
        PLANET_RADIUS
    );
    vec2 t2 = sphereIntersect(
        vec3(0.0, CAM_ALTITUDE, 0.0),
        params.rayDir,
        PLANET_CENTER,
        PLANET_RADIUS + ATMOSPHERE_HEIGHT
    );
    if (t2.y < 0.0) {
        transmittance = vec4(1.0);
        return vec3(0.0);
    }

    AtmosphericScattering atm = calcAtmosphereScattering(params, t1, t2);
    atm.densityR = pow(atm.densityR, 2.5);
    transmittance.rgb = exp(-atm.opticalDepth * (params.cRayleigh
        * atm.densityR
        + params.cMie
        * atm.densityM
        + params.cOzone
        * atm.densityR));
    transmittance.a = step(t1.x, 0.0);

    return atm.scattering * M_EXPOSURE;
}

vec3 calcAtmosphere(AtmosphereParams params) {
    vec2 t1 = sphereIntersect(
        vec3(0.0, CAM_ALTITUDE, 0.0),
        params.rayDir,
        PLANET_CENTER,
        PLANET_RADIUS
    );
    vec2 t2 = sphereIntersect(
        vec3(0.0, CAM_ALTITUDE, 0.0),
        params.rayDir,
        PLANET_CENTER,
        PLANET_RADIUS + ATMOSPHERE_HEIGHT
    );
    if (t2.y < 0.0) return vec3(0.0);

    AtmosphericScattering atm = calcAtmosphereScattering(params, t1, t2);
    return atm.scattering * M_EXPOSURE;
}

// what is this?!
void atmConstant(float rain, out vec3 cRayleigh, out vec3 cMie, out vec3 cOzone) {
    cRayleigh = mix(vec3(13.558e-6), vec3(5.802e-6, 13.558e-6, 33.100e-6), rain);
    cMie = mix(vec3(3.996e-6) * 10.0, vec3(3.996e-6), rain);
    cOzone = vec3(0.650e-6, 1.881e-6, 0.085e-6) * M_OZONE * rain;
}

vec3 calcAtmSky(vec3 worldDir, vec3 sunDir, vec3 moonDir, float rain) {
    vec3 cRayleigh, cMie, cOzone;
    atmConstant(rain, cRayleigh, cMie, cOzone);

    AtmosphereParams sunAtmParams = AtmosphereParams(
        cRayleigh,
        cMie,
        cOzone,
        worldDir,
        sunDir,
        1e10,
        1.0,
        1.0,
        rain
    );

    AtmosphereParams moonAtmParams = sunAtmParams;
    moonAtmParams.lightDir = moonDir;
    moonAtmParams.occlusion = 0.0;

    vec3 scattering = calcAtmosphere(sunAtmParams) * SUN_RADIANCE_MULTIPLIER;
    scattering += luminance(calcAtmosphere(moonAtmParams)) * MOON_RADIANCE_MULTIPLIER;
    return scattering;
}

void calcAtmLighting(
    vec3 sunDir,
    vec3 moonDir,
    float rain,
    out vec3 absorbColor,
    out vec3 scatterColor
) {
    vec3 cRayleigh, cMie, cOzone;
    atmConstant(rain, cRayleigh, cMie, cOzone);

    AtmosphereParams sunAtmParams = AtmosphereParams(
        cRayleigh,
        cMie,
        cOzone,
        vec3(0.0, 1.0, 0.0),
        sunDir,
        1e10,
        1.0,
        1.0,
        rain
    );

    AtmosphereParams moonAtmParams = sunAtmParams;
    moonAtmParams.lightDir = moonDir;

    absorbColor = calcLightTransmittance(sunDir.xyz, cRayleigh, cMie, cOzone, 0.75)
        * smoothstep(0.0, 0.1, sunDir.y) * SUN_RADIANCE_MULTIPLIER;
    absorbColor += calcLightTransmittance(moonDir.xyz, cRayleigh, cMie, cOzone, 0.0)
        * smoothstep(0.0, 0.1, moonDir.y) * MOON_RADIANCE_MULTIPLIER;

    scatterColor = calcAtmosphere(sunAtmParams) * SUN_RADIANCE_MULTIPLIER;
}

#endif
