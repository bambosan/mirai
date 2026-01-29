#ifndef IBL_INCLUDE
#define IBL_INCLUDE

uniform highp vec4 IBLParameters;
uniform highp vec4 Time;
SAMPLER2D_HIGHP_AUTOREG(s_BrdfLUT);

#if DO_INDIRECT_SPECULAR_SHADING_DUAL_TARGET_PASS || DO_INDIRECT_SPECULAR_SHADING_SINGLE_TARGET_PASS

uniform highp vec4 SSRParameters;
SAMPLER2D_HIGHP_AUTOREG(s_SSRTexture);

vec3 indirectSpecular(vec3 f0, vec3 worldDir, vec3 normal, vec3 scatterColor, vec3 absorbColor, vec2 ssrUV, float roughness, float metalness, vec2 lightmap, float exposure, bool isNeedSkyReflection) {
    vec3 blockAmbient = BLOCK_LIGHT_COLOR * uv1x2lig(lightmap.r) * BLOCK_LIGHT_INTENSITY;
    vec3 ambientColor = mix(vec3_splat(MIN_AMBIENT_LIGHT), blockAmbient, luminance(blockAmbient)) * metalness;
    vec3 incomingLight = ambientColor;

    if (IBLParameters.r != 0.0) {
        vec3 reflectedDir = reflect(worldDir, normal);
        vec3 skyReflection = GetAtmosphere(vec3(0.0, 100.0, 0.0), reflectedDir, 1e10, SunDir.xyz, vec3_splat(1.0)) * SUN_MAX_ILLUMINANCE;
        skyReflection += GetAtmosphere(vec3(0.0, 100.0, 0.0), reflectedDir, 1e10, MoonDir.xyz, vec3_splat(1.0)) * MOON_MAX_ILLUMINANCE;

        skyReflection = calcClouds(reflectedDir, SunDir.xyz, MoonDir.xyz, scatterColor, absorbColor, skyReflection, Time.x);

        if (isNeedSkyReflection) {
            float refIntensity = 1.0 - sqrt(roughness);
            incomingLight = mix(incomingLight, skyReflection * pow(lightmap.g, 3.0) * refIntensity, refIntensity);
        }

        float iblLuminance = luminance(incomingLight);
        float ambientLuminance = luminance(ambientColor);
        if (iblLuminance < ambientLuminance) {
            incomingLight = ambientColor;
        }

        if (SSRParameters.r != 0.0) {
            vec4 ssr = texture2D(s_SSRTexture, ssrUV);
            ssr.rgb = unExposeLighting(ssr.rgb, exposure);
            incomingLight = mix(incomingLight, ssr.rgb, ssr.a * SSRParameters.g);
        }
    }

    float cost = saturate(dot(-worldDir, normal));
    vec2 envDFGUV = vec2(cost, 1.0 - roughness);
    vec2 envDFG = texture2D(s_BrdfLUT, envDFGUV).rg;

    return incomingLight * (f0 * envDFG.r + envDFG.g);
}

#else

vec3 indirectSpecular(vec3 f0, vec3 worldDir, vec3 normal, vec3 scatterColor, vec3 absorbColor, float roughness, float metalness, vec2 lightmap, bool isNeedSkyReflection) {
    vec3 blockAmbient = BLOCK_LIGHT_COLOR * uv1x2lig(lightmap.r) * BLOCK_LIGHT_INTENSITY;
    vec3 ambientColor = mix(vec3_splat(MIN_AMBIENT_LIGHT), blockAmbient, luminance(blockAmbient)) * metalness;
    vec3 incomingLight = ambientColor;

    if (IBLParameters.r != 0.0) {
        vec3 reflectedDir = reflect(worldDir, normal);
        vec3 skyReflection = GetAtmosphere(vec3(0.0, 100.0, 0.0), reflectedDir, 1e10, SunDir.xyz, vec3_splat(1.0)) * SUN_MAX_ILLUMINANCE;
        skyReflection += GetAtmosphere(vec3(0.0, 100.0, 0.0), reflectedDir, 1e10, MoonDir.xyz, vec3_splat(1.0)) * MOON_MAX_ILLUMINANCE;

        skyReflection = calcClouds(reflectedDir, SunDir.xyz, MoonDir.xyz, scatterColor, absorbColor, skyReflection, Time.x);

        if (isNeedSkyReflection) {
            float refIntensity = 1.0 - sqrt(roughness);
            incomingLight = mix(incomingLight, skyReflection * pow(lightmap.g, 3.0) * refIntensity, refIntensity);
        }
    }

    float cost = saturate(dot(-worldDir, normal));
    vec2 envDFGUV = vec2(cost, 1.0 - roughness);
    vec2 envDFG = texture2D(s_BrdfLUT, envDFGUV).rg;

    return incomingLight * (f0 * envDFG.r + envDFG.g);
}

#endif
#endif //IBL_INCLUDE
