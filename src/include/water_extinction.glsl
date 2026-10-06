///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
in vec3 a_position;
in vec2 a_texcoord0;

layout(location = 0) out vec2 v_texcoord0;
layout(location = 1) out vec2 v_projPos;

void main() {
    v_texcoord0 = a_texcoord0;
    v_projPos = a_position.xy * 2.0 - 1.0;
    gl_Position = vec4(a_position.xy * 2.0 - 1.0, a_position.z, 1.0);
}
#endif

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
uniform mat4 u_invViewProj;

SAMPLER2D(s_SceneDepth);
SAMPLER2D(s_WaterDepth);

#include "lib/common.glsl"
#include "lib/space_transf.glsl"

layout(location = 0) in vec2 v_texcoord0;
layout(location = 1) in vec2 v_projPos;
out vec4 fragColor;

void main() {
    float depth0 = sampleDepth(s_SceneDepth, v_texcoord0);
    float depth1 = sampleDepth(s_WaterDepth, v_texcoord0);

    vec3 worldPos0 = projToWorld(vec3(v_projPos, depth0), u_invViewProj);
    vec3 worldPos1 = projToWorld(vec3(v_projPos, depth1), u_invViewProj);

    fragColor = vec4(exp(-WATER_EXTINCTION_COEFFICIENTS * distance(worldPos0, worldPos1)), 1.0);
}
#endif
