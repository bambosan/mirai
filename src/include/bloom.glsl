///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
uniform vec4 ViewportScale;

in vec3 a_position;
in vec2 a_texcoord0;

out vec2 v_texcoord0;

void main() {
    v_texcoord0 = a_texcoord0 * ViewportScale.xy;
    gl_Position = vec4(a_position.xy * 2.0 - 1.0, 0.0, 1.0);
}
#endif

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
// https://learnopengl.com/Guest-Articles/2022/Phys.-Based-Bloom
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
uniform vec4 ViewportScale;
uniform vec4 BloomParams;

#if BLOOM_BLEND_PASS
SAMPLER2D(s_HDRi);
#endif
SAMPLER2D(s_BlurPyramidTexture);

#include "lib/common.glsl"

in vec2 v_texcoord0;

out vec4 fragColor;

void main() {
    vec2 uv = (floor(ViewportScale.zw * ViewportScale.xy) - 0.5) / ViewportScale.zw;

#if BLOOM_BLEND_PASS || DF_UP_SAMPLE_PASS
    vec2 o = ViewportScale.xy / ViewportScale.zw;

    // Take 9 samples around current texel:
    // a - b - c
    // d - e - f
    // g - h - i
    // === ('e' is the current texel) ===
    vec3 a = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2(-o.x,  o.y), uv)).rgb;
    vec3 b = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2( 0.0,  o.y), uv)).rgb;
    vec3 c = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2( o.x,  o.y), uv)).rgb;

    vec3 d = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2(-o.x,  0.0), uv)).rgb;
    vec3 e = texture(s_BlurPyramidTexture, min(v_texcoord0, uv)).rgb;
    vec3 f = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2( o.x,  0.0), uv)).rgb;

    vec3 g = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2(-o.x, -o.y), uv)).rgb;
    vec3 h = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2( 0.0, -o.y), uv)).rgb;
    vec3 i = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2( o.x, -o.y), uv)).rgb;

    // Apply weighted distribution, by using a 3x3 tent filter:
    //  1   | 1 2 1 |
    // -- * | 2 4 2 |
    // 16   | 1 2 1 |
    vec3 bloom = e * 0.25 + (a + c + g + i) * 0.0625 + (b + d + f + h) * 0.125;

#if BLOOM_BLEND_PASS
    vec3 baseColor = texture(s_HDRi, v_texcoord0).rgb;
    fragColor = vec4(baseColor + bloom * BloomParams.r, 1.0);
#else
    fragColor = vec4(bloom, 1.0);
#endif
#endif

#if DF_DOWN_SAMPLE_PASS || THRESHOLDED_DOWN_SAMPLE_PASS
    vec2 o = 1.0 / ViewportScale.zw;

    // Take 13 samples around current texel:
    // a - b - c
    // - j - k -
    // d - e - f
    // - l - m -
    // g - h - i
    // === ('e' is the current texel) ===
    vec3 a = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2(-2.0 * o.x, 2.0 * o.y), uv)).rgb;
    vec3 b = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2(0.0, 2.0 * o.y), uv)).rgb;
    vec3 c = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2(2.0 * o.x, 2.0 * o.y), uv)).rgb;

    vec3 d = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2(-2.0 * o.x, 0.0), uv)).rgb;
    vec3 e = texture(s_BlurPyramidTexture, min(v_texcoord0, uv)).rgb;
    vec3 f = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2(2.0 * o.x, 0.0), uv)).rgb;

    vec3 g = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2(-2.0 * o.x, -2.0 * o.y), uv)).rgb;
    vec3 h = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2(0.0, -2.0 * o.y), uv)).rgb;
    vec3 i = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2(2.0 * o.x, -2.0 * o.y), uv)).rgb;

    vec3 j = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2(-o.x, o.y), uv)).rgb;
    vec3 k = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2(o.x, o.y), uv)).rgb;
    vec3 l = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2(-o.x, -o.y), uv)).rgb;
    vec3 m = texture(s_BlurPyramidTexture, min(v_texcoord0 + vec2(o.x, -o.y), uv)).rgb;

    // Apply weighted distribution:
    // 0.5 + 0.125 + 0.125 + 0.125 + 0.125 = 1
    // a,b,d,e * 0.125
    // b,c,e,f * 0.125
    // d,e,g,h * 0.125
    // e,f,h,i * 0.125
    // j,k,l,m * 0.5
    // This shows 5 square areas that are being sampled. But some of them overlap,
    // so to have an energy preserving downsample we need to make some adjustments.
    // The weights are the distributed, so that the sum of j,k,l,m (e.g.)
    // contribute 0.5 to the final color output. The code below is written
    // to effectively yield this sum. We get:
    // 0.125*5 + 0.03125*4 + 0.0625*4 = 1
    vec3 outColor = e * 0.125 + (a + c + g + i) * 0.03125 + (b + d + f + h) * 0.0625
        +  (j + k + l + m) * 0.125;

    outColor = max(outColor, vec3(EPSILON));
    fragColor = vec4(outColor, 1.0);
#endif
}
#endif
