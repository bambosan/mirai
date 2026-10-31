#ifndef NOISES_INCLUDED
#define NOISES_INCLUDED

SAMPLER2DARRAY(s_CausticsTexture);

// perlin worley are precomputed in the texture atlas
// the atlas is a 6*6 grid of 32*32 tiles with 1 px padding each side
// inspired from https://www.shadertoy.com/view/3sffzj
// do biniear filtering because s_CausticsTexture is nearest

float worleyR(vec2 uv) {
    uv -= 0.5;
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    vec4 t = textureGather(s_CausticsTexture, vec3((i + 0.5) * 0.00390625, 3.0), 0);
    return mix(mix(t.w, t.z, f.x), mix(t.x, t.y, f.x), f.y);
}

float worleyG(vec2 uv) {
    uv -= 0.5;
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    vec4 t = textureGather(s_CausticsTexture, vec3((i + 0.5) * 0.00390625, 3.0), 1);
    return mix(mix(t.w, t.z, f.x), mix(t.x, t.y, f.x), f.y);
}

float worley3d(vec3 pos) {
    pos = mod(pos, vec3(32.0, 32.0, 36.0));

    float col = mod(floor(pos.z), 6.0) * 34.0;
    float row = floor(pos.z / 6.0) * 34.0;
    vec2 uv = vec2(pos.x + col, pos.y - 34.0 - row) + 1.0;

    float a = worleyR(uv);
    float b = worleyG(uv);

    return mix(a, b, fract(pos.z));
}

float perlinWorleyR(vec2 uv) {
    uv -= 0.5;
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    vec4 t = textureGather(s_CausticsTexture, vec3((i + 0.5) * 0.00390625, 4.0), 0);
    return mix(mix(t.w, t.z, f.x), mix(t.x, t.y, f.x), f.y);
}

float perlinWorleyG(vec2 uv) {
    uv -= 0.5;
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    vec4 t = textureGather(s_CausticsTexture, vec3((i + 0.5) * 0.00390625, 4.0), 1);
    return mix(mix(t.w, t.z, f.x), mix(t.x, t.y, f.x), f.y);
}

float perlinWorley3d(vec3 pos) {
    pos = mod(pos, vec3(32.0, 32.0, 36.0));

    float col = mod(floor(pos.z), 6.0) * 34.0;
    float row = floor(pos.z / 6.0) * 34.0;
    vec2 uv = vec2(pos.x + col, pos.y - 34.0 - row) + 1.0;

    float a = perlinWorleyR(uv);
    float b = perlinWorleyG(uv);

    return mix(a, b, fract(pos.z));
}

float worley2d(vec2 uv) {
    uv -= 0.5;
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    vec4 t = textureGather(s_CausticsTexture, vec3((i + 0.5) * 0.00390625, 2.0), 0);
    return mix(mix(t.w, t.z, f.x), mix(t.x, t.y, f.x), f.y);
}

float perlinNoise(vec2 uv) {
    uv -= 0.5;
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    vec4 t = textureGather(s_CausticsTexture, vec3((i + 0.5) * 0.00390625, 0.0), 0);
    return mix(mix(t.w, t.z, f.x), mix(t.x, t.y, f.x), f.y);
}

#endif
