#ifndef WATER_WAVE_INCLUDED
#define WATER_WAVE_INCLUDED

// https://www.shadertoy.com/view/MdXyzX

#define WAVE_OCTAVES 10
#define WAVE_POS_SCALE vec2(2.0, 3.5)
#define WAVE_DRIFT 2.0
#define WAVE_FREQ_BASE 1.0
#define WAVE_SPEED_BASE 2.0
#define WAVE_ANGLE_STEP 1.1
#define WAVE_FREQ_STEP 1.12
#define WAVE_SPEED_STEP 1.05
#define WAVE_WEIGHT_STEP 0.8
#define WAVE_WARP_STEP 0.9

vec2 wavedx(vec2 pos, vec2 dir, float speed, float freq, float time) {
    float x = dot(dir, pos) * freq - time * speed;
    float wave = exp(sin(x) - 1.0);
    return vec2(wave, -wave * cos(x));
}

float waveField(vec2 pos, float time, float weightStep, bool warp) {
    float freq = WAVE_FREQ_BASE;
    float speed = WAVE_SPEED_BASE;
    float angle = 0.0;
    float weight = 1.0;
    float w = 0.0;
    float ws = 0.0;

    pos *= WAVE_POS_SCALE;
    pos.y += time * WAVE_DRIFT;

    for (int i = 0; i < WAVE_OCTAVES; ++i) {
        vec2 dir = vec2(sin(angle), cos(angle));
        vec2 res = wavedx(pos, dir, speed, freq, time);
        if (warp) pos += dir * res.y * weight;

        w += res.x * weight;
        ws += weight;
        angle += WAVE_ANGLE_STEP;
        weight *= weightStep;
        freq *= WAVE_FREQ_STEP;
        speed *= WAVE_SPEED_STEP;
    }

    return w / ws;
}

float waves1(vec2 pos, float time) {
    return clamp(waveField(pos, time, WAVE_WEIGHT_STEP, false), 0.0, 1.0);
}

float waves2(vec2 pos, float time) {
    return smoothstep(0.2, 1.0, waveField(pos, time, WAVE_WARP_STEP, true));
}

vec3 calcWaterNormal(vec2 pos, float time, float d) {
    float hL = waves1(pos - vec2(d, 0.0), time);
    float hR = waves1(pos + vec2(d, 0.0), time);
    float hD = waves1(pos - vec2(0.0, d), time);
    float hU = waves1(pos + vec2(0.0, d), time);
    return normalize(vec3(hL - hR, hD - hU, 1.0));
}

// projected height map, sampled along the refracted light direction
float calcCaustic(vec3 position, vec3 lightDir, float time) {
    vec3 rL = refract(-lightDir, vec3(0.0, 1.0, 0.0), 0.75);
    vec3 pL = rL * position.y / rL.y;
    vec3 ppos = position - pL;
    return waves2(ppos.xz, time);
}

#endif
