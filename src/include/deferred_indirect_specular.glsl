///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
#if FALLBACK_PASS
void main() {
    gl_Position = vec4(0.0);
}
#else
in vec3 a_position;
in vec2 a_texcoord0;

#if DO_INDIRECT_SPECULAR_SHADING_PASS
layout(location = 1) out vec2 v_projPos;
#endif
layout(location = 0) out vec2 v_texcoord0;

void main() {
    v_texcoord0 = a_texcoord0;
#if DO_INDIRECT_SPECULAR_SHADING_PASS
    v_projPos = a_position.xy * 2.0 - 1.0;
#endif
    gl_Position = vec4(a_position.xy * 2.0 - 1.0, a_position.z, 1.0);
}
#endif
#endif //SHADER_STAGE__VERTEX

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
#if FALLBACK_PASS
out vec4 fragColor;
void main() {
    fragColor = vec4(0.0);
}
#endif //FALLBACK_PASS

#if DO_INDIRECT_SPECULAR_SHADING_PASS
uniform vec4 ConvolutionType;
uniform vec4 IBLParameters;
uniform vec4 LastSpecularIBLIdx;
uniform vec4 FogAndDistanceControl;
uniform vec4 SSRParameters;
uniform mat4 u_invViewProj;

SAMPLER2D(s_ColorMetalnessSubsurface);
SAMPLER2D(s_Normal);
SAMPLER2D(s_PreviousFrameAverageLuminance);
SAMPLER2D(s_SceneDepth);
USAMPLER2D(s_EmissiveAmbientLinearRoughness);

#include "lib/materials.glsl"
#include "lib/ibl.glsl"
#include "lib/space_transf.glsl"

layout(location = 0) in vec2 v_texcoord0;
layout(location = 1) in vec2 v_projPos;

out vec4 fragColor;

void main() {
    float depth = sampleDepth(s_SceneDepth, v_texcoord0);
    vec3 outColor = vec3(0.0);

    if (depth < 1.0) {
        vec3 projPos = vec3(v_projPos, depth);
        vec3 worldPos = projToWorld(projPos, u_invViewProj);
        vec3 worldDir = normalize(worldPos);

        uvec4 data16 = texelFetch(s_EmissiveAmbientLinearRoughness,
            ivec2(gl_FragCoord.xy), 0) & 0xFFFFu;
        float skyLightmap = float(data16.a & 0xFFu) * (1.0 / 255.0);
        float roughness = float(data16.r >> 8) * (1.0 / 255.0);
        float vanillaAO = float(data16.a >> 8) * (1.0 / 255.0);

        vec4 data = texture(s_ColorMetalnessSubsurface, v_texcoord0);
        float metalness = unpackMetalness(data.a);
        vec3 albedo = toLinear(data.rgb);
        vec3 f0 = mix(DEFAULT_F0, albedo, metalness);

        vec3 normal = octToNdirSnorm(texture(s_Normal, v_texcoord0).rg);

        float exposure = texture(s_PreviousFrameAverageLuminance, vec2(0.5)).r;

        if (!(FogAndDistanceControl.r < EPSILON)) {
            float occluder = linearstep(0.85, 1.0, skyLightmap) * vanillaAO * vanillaAO;
            outColor = indirectSpecular(
                IBLParameters,
                SSRParameters,
                f0,
                worldDir,
                normal,
                v_texcoord0,
                ConvolutionType.r,
                LastSpecularIBLIdx.r,
                roughness,
                occluder,
                exposure
            );
        }
        outColor = preExposeLighting(outColor.rgb * EXPOSURE_MULTIPLIER, exposure);
    }

    fragColor = vec4(outColor, 1.0);
}
#endif //DO_INDIRECT_SPECULAR_SHADING_PASS

#if DO_INDIRECT_SPECULAR_UPSCALE_PASS
SAMPLER2D(s_SpecularLighting);
SAMPLER2D(s_SceneDepth);

layout(location = 0) in vec2 v_texcoord0;
out vec4 fragColor;

void main() {
    fragColor = vec4(0.0);
    if (texture(s_SceneDepth, v_texcoord0).r < 1.0)
        fragColor.rgb = texture(s_SpecularLighting, v_texcoord0).rgb;
}
#endif //DO_INDIRECT_SPECULAR_UPSCALE_PASS
#endif //SHADER_STAGE__FRAGMENT
