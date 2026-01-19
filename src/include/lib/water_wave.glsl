#ifndef WATER_WAVE_INCLUDE
#define WATER_WAVE_INCLUDE

vec2 wavedx(vec2 pos, vec2 dir, float speed, float freq, float time) {
    float x = dot(dir, pos) * freq + time * speed;
    float wave = exp(sin(x) - 1.0);
    return vec2(wave, -wave * cos(x));
}

float getWaves(vec2 pos, float time) {
    float angle = 0.0;
    float phase = 6.0;
    float speed = 2.0;
    float weight = 1.0;
    float w = 0.0;
    float ws = 0.0;

    for (int i = 0; i < 15; i++) {
        vec2 dir = vec2(sin(angle), cos(angle));
        vec2 res = wavedx(pos, dir, speed, phase, time);
        pos += dir * res.y * weight * 0.02;
        w += res.x * weight;
        ws += weight;
        angle += 12.0;
        weight *= 0.8;
        phase *= 1.18;
        speed *= 1.07;
    }

    return w / ws;
}

vec3 getWaterNormal(vec2 pos, float time) {

    float hL = getWaves(pos - vec2(0.025, 0.0), time);
    float hR = getWaves(pos + vec2(0.025, 0.0), time);
    float hD = getWaves(pos - vec2(0.0, 0.025), time);
    float hU = getWaves(pos + vec2(0.0, 0.025), time);

    return normalize(vec3(hL - hR, hD - hU, 1.0));
}

float calcCaustic(vec3 position, vec3 lightDir, float time) {
    CONST(vec3) up = vec3(0.0, 1.0, 0.0);
    vec3 rL = refract(-lightDir, up, 0.75);
    vec3 pL = rL * position.y / rL.y;
    vec3 ppos = position - pL;
    vec3 pnormal = getWaterNormal(ppos.xz * 0.15, time);
    vec3 rN = refract(-up, pnormal.xzy, 0.75);
    vec3 tpos = (position + up) - rN / rN.y;
    return smoothstep(0.0, 0.2, distance(tpos, position)) * 15.0;
}

#endif
