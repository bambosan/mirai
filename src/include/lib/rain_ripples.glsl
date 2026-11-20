#ifndef RAIN_RIPPLES_INCLUDED
#define RAIN_RIPPLES_INCLUDED

#define RIPPLE_FRAMES          32.0
#define RIPPLE_SIZE            128.0
#define RIPPLE_FPS             60.0
#define RIPPLE_SPAN            1.0
#define RIPPLE_COVER           1.0
#define RIPPLE_STRENGTH        1.0
#define RIPPLE_CELLS_PER_METER 1.5

vec2 rippleFetch(sampler2D tex, vec2 quadUV, float frame) {
    float halfTexel = 0.5 / RIPPLE_SIZE;
    vec2 frameUV = clamp(vec2(quadUV.x, 1.0 - quadUV.y), halfTexel, 1.0 - halfTexel);
    float frameIdx = clamp(frame, 0.0, RIPPLE_FRAMES - 1.0);
    vec4 texel = textureLod(tex, vec2(frameUV.x, (frameIdx + frameUV.y) / RIPPLE_FRAMES), 0.0);
    return (texel.rg * 255.0 - 128.0) / 127.0;
}

vec4 rippleHash(vec2 seed) {
    seed = mod(seed, 251.0);
    return fract(sin(vec4(dot(seed, vec2(127.1, 311.7)), dot(seed, vec2(269.5, 183.3)),
        dot(seed, vec2(419.2, 371.9)), dot(seed, vec2(83.7, 229.1)))) * 43758.5453);
}

vec2 rippleAt(sampler2D tex, vec2 samplePos, vec2 cellId, float time) {
    vec4 cellRand = rippleHash(cellId);
    float cycleTime = time * (RIPPLE_FPS / RIPPLE_FRAMES) * (0.85 + 0.3 * cellRand.w) + cellRand.z;
    float cycleIdx = floor(cycleTime);
    float cycleProg = cycleTime - cycleIdx;

    vec4 dropRand = rippleHash(cellId * 1.3 + vec2(0.37, 0.71) * mod(cycleIdx, 97.0));
    if (dropRand.w > RIPPLE_COVER) return vec2(0.0);

    vec2 dropCenter = cellId + 0.15 + 0.7 * dropRand.xy;
    float dropSize = RIPPLE_SPAN * (0.75 + 0.5 * dropRand.z);
    vec2 quadUV = (samplePos - dropCenter) / dropSize + 0.5;
    if (any(lessThan(quadUV, vec2(0.0))) || any(greaterThan(quadUV, vec2(1.0)))) return vec2(0.0);

    float framePos = cycleProg * RIPPLE_FRAMES;
    float frameBase = floor(framePos);
    vec2 dropSlope = mix(
        rippleFetch(tex, quadUV, frameBase),
        rippleFetch(tex, quadUV, frameBase + 1.0),
        framePos - frameBase
    );
    return dropSlope * (0.6 + 0.8 * dropRand.y);
}

vec2 rippleField(sampler2D tex, vec2 samplePos, float time) {
    vec2 baseCell = floor(samplePos);
    vec2 rippleSum = vec2(0.0);
    for (int offY = -1; offY <= 1; offY++)
        for (int offX = -1; offX <= 1; offX++)
            rippleSum += rippleAt(tex, samplePos, baseCell + vec2(float(offX), float(offY)), time);
    return rippleSum;
}

#endif
