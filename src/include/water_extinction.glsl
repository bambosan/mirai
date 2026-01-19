#if BGFX_SHADER_TYPE_VERTEX
void main() {
    gl_Position = vec4(a_position.xy * 2.0 - 1.0, a_position.z, 1.0);
    v_texcoord0 = a_texcoord0;
    v_projPos = gl_Position.xy;
}
#endif

#if BGFX_SHADER_TYPE_FRAGMENT
SAMPLER2D_HIGHP_AUTOREG(s_SceneDepth);
SAMPLER2D_HIGHP_AUTOREG(s_WaterDepth);

#include "./lib/common.glsl"

vec3 projToWorld(vec3 projPos) {
    vec4 worldPos = mul(u_invViewProj, vec4(projPos, 1.0));
    return worldPos.xyz / worldPos.w;
}

void main() {
    float depth0 = sampleDepth(s_SceneDepth, v_texcoord0);
    float depth1 = sampleDepth(s_WaterDepth, v_texcoord0);

    vec3 worldPos0 = projToWorld(vec3(v_projPos, depth0));
    vec3 worldPos1 = projToWorld(vec3(v_projPos, depth1));

    gl_FragColor = vec4(exp(-WATER_EXTINCTION_COEFFICIENTS * distance(worldPos0, worldPos1)), 1.0);
}
#endif
