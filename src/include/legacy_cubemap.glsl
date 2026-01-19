#if BGFX_SHADER_TYPE_VERTEX
uniform mat4 CubemapRotation;

void main() {
    v_texcoord0 = a_texcoord0;
    gl_Position = mul(u_modelViewProj, mul(CubemapRotation, vec4(a_position, 1.0)));
}
#endif

#if BGFX_SHADER_TYPE_FRAGMENT
#include "./lib/common.glsl"

SAMPLER2D_HIGHP_AUTOREG(s_MatTexture);
SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);

void main() {
#if FORCE_FORWARD_PBR_OPAQUE_PASS
    vec4 albedo = texture2D(s_MatTexture, v_texcoord0);
    albedo.rgb = preExposeLighting(albedo.rgb, texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r);
    gl_FragColor = albedo;
#endif

#if TRANSPARENT_PASS
    vec4 albedo = texture2D(s_MatTexture, v_texcoord0);
    gl_FragColor = albedo;
#endif

#if TRANSPARENT_DEGAMMA_PASS
    vec4 albedo = texture2D(s_MatTexture, v_texcoord0);
    albedo.rgb = pow(albedo.rgb, vec3_splat(2.2));
    gl_FragColor = albedo;
#endif
}
#endif
