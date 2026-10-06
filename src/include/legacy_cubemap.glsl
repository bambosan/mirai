#if SHADER_STAGE__VERTEX
uniform mat4 CubemapRotation;
uniform mat4 u_modelViewProj;

in vec3 a_position;
in vec2 a_texcoord0;

out vec2 v_texcoord0;

void main() {
    v_texcoord0 = a_texcoord0;
    gl_Position = u_modelViewProj * CubemapRotation * vec4(a_position, 1.0);
}
#endif

#if SHADER_STAGE__FRAGMENT
SAMPLER2D(s_MatTexture);
SAMPLER2D(s_PreviousFrameAverageLuminance);

#include "lib/common.glsl"

in vec2 v_texcoord0;
out vec4 fragColor;

void main() {
#if FORCE_FORWARD_PBR_OPAQUE_PASS
    vec4 albedo = texture(s_MatTexture, v_texcoord0);
    albedo.rgb = preExposeLighting(albedo.rgb, texture(s_PreviousFrameAverageLuminance,
        vec2(0.5)).r);
    fragColor = albedo;
#endif

#if TRANSPARENT_PASS
    vec4 albedo = texture(s_MatTexture, v_texcoord0);
    fragColor = albedo;
#endif

#if TRANSPARENT_DEGAMMA_PASS
    vec4 albedo = texture(s_MatTexture, v_texcoord0);
    albedo.rgb  = toLinear(albedo.rgb);
    fragColor = albedo;
#endif
}
#endif
