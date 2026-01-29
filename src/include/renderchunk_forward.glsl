#include "./lib/taau_util.glsl"
#include "./lib/common.glsl"
#include "./lib/atmosphere.glsl"

#if BGFX_SHADER_TYPE_VERTEX
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 DimensionID;

void main() {
#if INSTANCING__ON
    vec3 worldPos = mul(mtxFromCols(i_data1, i_data2, i_data3, vec4(0.0, 0.0, 0.0, 1.0)), vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = mul(u_model[0], vec4(a_position, 1.0)).xyz;
#endif
    v_texcoord0 = a_texcoord0;

#if !DEPTH_ONLY_PASS && !DEPTH_ONLY_OPAQUE_PASS
    uint data16 = uint(round(a_texcoord1.y * 65535.0));
    v_lightmapUV = vec2(uvec2(data16 >> 4u, data16) & uvec2(15u, 15u)) / 15.0;
    v_pbrTextureId = a_texcoord4 & 0xffff;

    v_normal = mul(u_model[0], vec4(a_normal.xyz, 0.0)).xyz;
    v_tangent = mul(u_model[0], vec4(a_tangent.xyz, 0.0)).xyz;
    v_bitangent = mul(u_model[0], vec4(cross(a_normal.xyz, a_tangent.xyz) * a_tangent.w, 0.0)).xyz;
    v_worldPos = worldPos;
    v_color0 = a_color0;
    v_clipPos = mul(u_modelViewProj, vec4(worldPos, 1.0));

    v_absorbColor = GetLightTransmittance(SunDir.xyz) * SUN_MAX_ILLUMINANCE;
    v_absorbColor += GetLightTransmittance(MoonDir.xyz) * MOON_MAX_ILLUMINANCE;
    v_scatterColor = GetAtmosphere(vec3(0.0, 100.0, 0.0), vec3(0.0, 1.0, 0.0), 1e10, SunDir.xyz, vec3_splat(1.0)) * SUN_MAX_ILLUMINANCE;
    v_scatterColor += GetAtmosphere(vec3(0.0, 100.0, 0.0), vec3(0.0, 1.0, 0.0), 1e10, MoonDir.xyz, vec3_splat(1.0)) * MOON_MAX_ILLUMINANCE;

    if (DimensionID.r != 0.0) {
        v_absorbColor = vec3_splat(0.0);
        v_scatterColor = vec3_splat(1.0);
    }

    gl_Position = jitterVertexPosition(worldPos);
#else
    gl_Position = mul(u_viewProj, vec4(worldPos, 1.0));
#endif
}
#endif

#if BGFX_SHADER_TYPE_FRAGMENT

SAMPLER2D_HIGHP_AUTOREG(s_MatTexture);
SAMPLER2D_HIGHP_AUTOREG(s_LightMapTexture);

#if !DEPTH_ONLY_PASS && !DEPTH_ONLY_OPAQUE_PASS
uniform highp vec4 CameraIsUnderwater;
uniform highp vec4 CausticsParameters;
uniform highp vec4 CameraLightIntensity;
uniform highp vec4 DirectionalLightSourceWorldSpaceDirection;
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 DimensionID;
uniform highp vec4 FogAndDistanceControl;
uniform highp vec4 FogColor;
uniform highp vec4 RenderChunkFogAlpha;

SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);
SAMPLER2DARRAY_AUTOREG(s_ScatteringBuffer);

#include "./lib/materials.glsl"
#include "./lib/shadow.glsl"
#include "./lib/bsdf.glsl"
#include "./lib/ibl.glsl"
#include "./lib/froxel_util.glsl"
#endif

void main() {
#if DEPTH_ONLY_PASS
    if (texture2D(s_MatTexture, v_texcoord0).a < 0.5) discard;
    gl_FragData[0] = vec4_splat(0.0);
#elif DEPTH_ONLY_OPAQUE_PASS
    gl_FragData[0] = vec4_splat(0.0);
#else
    vec4 albedo = texture2D(s_MatTexture, v_texcoord0);
    albedo.rgb *= v_color0.rgb;
    albedo.rgb = pow(albedo.rgb, vec3_splat(2.2));

    vec3 normal = gl_FrontFacing ? -v_normal : v_normal;
    normal = normalize(normal);
    vec4 mers = vec4(0.0, 0.0, 1.0, 0.0);
    getTexturePBRMaterials(s_MatTexture, v_pbrTextureId, v_texcoord0, v_tangent, v_bitangent, normal, mers);
    vec3 f0 = mix(vec3_splat(0.02), albedo.rgb, mers.r);

    vec3 blockAmbient = BLOCK_LIGHT_COLOR * uv1x2lig(v_lightmapUV.r) * BLOCK_LIGHT_INTENSITY;
    vec3 skyAmbient = mix(pow(v_lightmapUV.g, 3.0), pow(v_lightmapUV.g, 5.0), CameraLightIntensity.g) * v_scatterColor * SKY_LIGHT_INTENSITY;
    vec3 outColor = albedo.rgb * (1.0 - mers.r) * max(blockAmbient + skyAmbient, vec3_splat(MIN_AMBIENT_LIGHT));
    vec2 shadowMap = calcShadowMap(v_worldPos, normal);
    vec3 worldDir = normalize(v_worldPos);
    vec3 bsdf = BSDF(normal, DirectionalLightSourceWorldSpaceDirection.xyz, -worldDir, f0, albedo.rgb, shadowMap, mers.r, mers.b, mers.a);

    outColor += bsdf * v_absorbColor;
    outColor += albedo.rgb * mers.g * EMISSIVE_MATERIAL_INTENSITY;

    bool isCameraInsideWater = CameraIsUnderwater.r != 0.0 && CausticsParameters.a != 0.0;
    outColor += indirectSpecular(f0, worldDir, normal, v_scatterColor, v_absorbColor, mers.b, mers.r, v_lightmapUV, !isCameraInsideWater);

    float worldDist = length(v_worldPos);

    if (DimensionID.r == 0.0) {
        vec3 scattering = GetAtmosphere(vec3(0.0, 100.0, 0.0), worldDir, 1e10, SunDir.xyz, vec3_splat(1.0)) * SUN_MAX_ILLUMINANCE;
        scattering += GetAtmosphere(vec3(0.0, 100.0, 0.0), worldDir, 1e10, MoonDir.xyz, vec3_splat(1.0)) * MOON_MAX_ILLUMINANCE;

        float fogBlend = calculateFogIntensityVanilla(worldDist, FogAndDistanceControl.z, 0.92, 1.0);
        outColor = mix(outColor, scattering, fogBlend);

        if (isCameraInsideWater) outColor *= exp(-WATER_EXTINCTION_COEFFICIENTS * worldDist);

        if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.x != 0.0) {
            vec3 projPos = v_clipPos.xyz / v_clipPos.w;
            vec3 uvw = ndcToVolume(projPos);
            vec4 volumetricFog = sampleVolume(s_ScatteringBuffer, uvw);
            outColor = outColor * volumetricFog.a + volumetricFog.rgb;
        }
    } else {
        float fogBlend = calculateFogIntensityFaded(worldDist, FogAndDistanceControl.z, FogAndDistanceControl.x, FogAndDistanceControl.y, RenderChunkFogAlpha.x);
        outColor = mix(outColor, pow(FogColor.rgb, vec3_splat(2.2)), fogBlend);
    }

    outColor = preExposeLighting(outColor, texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r);

    gl_FragData[0] = vec4(outColor, albedo.a);
#endif
}
#endif
