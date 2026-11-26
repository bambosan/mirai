#include "lib/bgfx_uniforms.glsl"

///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
in vec3 a_position;
in vec2 a_texcoord0;

#if !SSR_RAY_MARCH_HZB_PASS
layout(location = 0) out vec2 v_texcoord0;
#endif
#if SSR_RAY_MARCH_PASS
layout(location = 1) out vec2 v_projPos;
#endif

void main() {
#if !SSR_RAY_MARCH_HZB_PASS
    v_texcoord0 = a_texcoord0;
#endif
#if SSR_RAY_MARCH_PASS
    v_projPos = a_position.xy * 2.0 - 1.0;
#endif
    gl_Position = vec4(a_position.xy * 2.0 - 1.0, 0.0, 1.0);
}
#endif

///////////////////////////////////////////////////////////
// FRAGMENT SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__FRAGMENT
uniform vec4 SSRRoughnessCutoffParams;
uniform vec4 SSRRayMarchingParams;
uniform vec4 SSRFadingParamsAndThickness;
uniform vec4 SSRTemporalAccumulationParams;
uniform vec4 CameraData;
uniform vec4 ScreenSize;
uniform vec4 ViewportScale;

SAMPLER2D(s_GbufferDepth);
SAMPLER2D(s_GbufferNormal);
SAMPLER2D(s_InputTexture);
SAMPLER2D(s_RasterColor);
SAMPLER2D(s_PreviousReflectionBuffer);
USAMPLER2D(s_GbufferRoughness);

#include "lib/common.glsl"
#include "lib/materials.glsl"
#include "lib/space_transf.glsl"

vec2 getPreviousUV(vec3 ndc) {
    vec3 worldPos = projToWorld(ndc, u_invViewProj);
    vec4 prevClipPos = u_prevViewProj * vec4(worldPos, 1.0);
    vec3 prevNdc = prevClipPos.xyz / prevClipPos.w;
    vec2 prevUV = prevNdc.xy * 0.5 + 0.5;
    return prevUV;
}

bool isDepthInCameraBounds(float depth) {
    if (CameraData.x < CameraData.y) return CameraData.x < depth && depth < CameraData.y;
    return CameraData.x > depth && depth > CameraData.y;
}

float projToLinearDepth(float z) {
#if TRANSPILE_TARGET__GLSL
    return CameraData.x * (z + 1.0)
        / (CameraData.y + CameraData.x - z * (CameraData.y - CameraData.x));
#else
    return -z / (CameraData.y - z * (CameraData.y - CameraData.x));
#endif
}

float calcRoughnessFading(float roughness) {
    float roughnessFadeDist = SSRRoughnessCutoffParams.x - SSRRoughnessCutoffParams.y;
    float roughnessLerpAlpha = (max(roughness, SSRRoughnessCutoffParams.y)
        - SSRRoughnessCutoffParams.y) / roughnessFadeDist;
    float fadeValueRoughness = mix(1.0, 0.0, roughnessLerpAlpha);
    return fadeValueRoughness;
}

float calcPixelsToExit(vec3 rayStartSS, vec3 dir) {
#if TRANSPILE_TARGET__GLSL
    const float zMin = -1.0;
#else
    const float zMin = 0.0;
#endif
    float tx = dir.x < 0.0 ? -rayStartSS.x / dir.x : (1.0 - rayStartSS.x) / dir.x;
    float ty = dir.y < 0.0 ? -rayStartSS.y / dir.y : (1.0 - rayStartSS.y) / dir.y;
    float tz = dir.z < 0.0 ? (zMin - rayStartSS.z) / dir.z : (1.0 - rayStartSS.z) / dir.z;
    return max(min(min(tx, ty), tz), 0.0);
}

int doLinearSearch(
    vec3 rayStartSS,
    vec3 rayStepSS,
    int stepsCount,
    inout vec3 foundCoord
) {
    int foundIter = -1;
    float prevRayDepth = projToLinearDepth(rayStartSS.z);

    for (int i = 1; i <= stepsCount; i++) {
        vec3 posSS = rayStartSS + rayStepSS * float(i);
        float rayLinearDepth = projToLinearDepth(posSS.z);
        float sceneDepth = sampleDepth(s_GbufferDepth, posSS.xy);
        float sceneLinearDepth = projToLinearDepth(sceneDepth);

        float thickness = smoothstep(0.0, 0.01, sceneLinearDepth) * 0.75 + 0.25;
        if (sceneLinearDepth <= rayLinearDepth
            && prevRayDepth <= (sceneLinearDepth + sceneLinearDepth * thickness)) {
            foundIter = i;
            foundCoord = posSS;
            break;
        }

        prevRayDepth = rayLinearDepth;
    }

    return foundIter;
}

// void doBinarySearch(
//     int foundIter,
//     vec3 rayStartSS,
//     vec3 rayStepSS,
//     inout vec3 foundCoord
// ) {
//     float iterBeforeHit = float(foundIter - 1);
//     float iterAfterHit = float(foundIter);
//     int bStepCount = int(SSRRayMarchingParams.w);
//
//     for (int i = 0; i < bStepCount; i++) {
//         float iterMid = (iterBeforeHit + iterAfterHit) * 0.5;
//         vec3 posMid = rayStartSS + (rayStepSS * iterMid);
//         float rayLinearDepth = projToLinearDepth(posMid.z);
//         float sceneDepth = sampleDepth(s_GbufferDepth, posMid.xy);
//         float sceneLinearDepth = projToLinearDepth(sceneDepth);
//
//         if (rayLinearDepth > sceneLinearDepth) {
//             iterAfterHit = iterMid;
//             foundCoord = posMid;
//         } else {
//             iterBeforeHit = iterMid;
//         }
//     }
// }

#if !SSR_RAY_MARCH_HZB_PASS
layout(location = 0) in vec2 v_texcoord0;
#endif
#if SSR_RAY_MARCH_PASS
layout(location = 1) in vec2 v_projPos;
#endif

out vec4 fragData0;

void main() {
#if SSR_RAY_MARCH_PASS
    fragData0 = vec4(0.0, 0.0, 0.0, -1.0);

    uvec4 data16 = texelFetch(s_GbufferRoughness, ivec2(gl_FragCoord.xy), 0) & 0xFFFFu;
    float roughness = float(data16.r >> 8) / 255.0;
    if (roughness > SSRRoughnessCutoffParams.x) return;

    float depth = sampleDepth(s_GbufferDepth, v_texcoord0);
    vec3 viewPos = projToView(vec3(v_projPos, depth), u_invProj);
    vec3 normal = octToNdirSnorm(texture(s_GbufferNormal, v_texcoord0).rg);
    vec3 viewNormal = (u_view * vec4(normal, 0.0)).xyz;

    vec3 reflectedView = reflect(normalize(viewPos), viewNormal);
    vec3 rayEndView = viewPos + reflectedView;

    if (!isDepthInCameraBounds(viewPos.z) || !isDepthInCameraBounds(rayEndView.z)) return;

    vec3 rayStartSS = viewToProj(viewPos, u_proj);
    vec3 rayEndSS = viewToProj(rayEndView, u_proj);
    vec3 raySpanSS = rayEndSS - rayStartSS;
    vec2 raySpanPx = raySpanSS.xy * ScreenSize.xy;
    float majorPx = max(abs(raySpanPx.x), abs(raySpanPx.y));
    if (majorPx < EPSILON) return;

    vec3 dirPerPx = raySpanSS / majorPx;
    float pxToExit = calcPixelsToExit(rayStartSS, dirPerPx);
    float stridePx = max(1.0, pxToExit / 20.0);
    int stepsCount = int(pxToExit / stridePx);

    vec3 rayStepSS = dirPerPx * stridePx;

    float ign = fract(dot(floor(gl_FragCoord.xy), vec2(0.06711056, 0.00583715)) * 52.9829189);
    rayStartSS += rayStepSS * ign;

    vec3 foundCoord = vec3(0.0);
    int foundIter = doLinearSearch(rayStartSS, rayStepSS, stepsCount, foundCoord);
    if (foundIter < 1) return;

    // doBinarySearch(foundIter, rayStartSS, rayStepSS, foundCoord);

    if (foundCoord.x > 0.0 && foundCoord.x < 1.0
        && foundCoord.y > 0.0 && foundCoord.y < 1.0
        && foundCoord.z < 1.0) {
        fragData0.rgb = foundCoord;
        fragData0.a = calcRoughnessFading(roughness);
    }
#endif

// currently unused
#if SSR_RAY_MARCH_HZB_PASS
    fragData0 = vec4(0.0);
#endif

// skip
#if SSR_FILL_GAPS_PASS
    fragData0 = texture(s_InputTexture, v_texcoord0);
#endif

#if SSR_GET_REFLECTED_COLOR_PASS
    vec4 hitData = texture(s_InputTexture, v_texcoord0);
    if (hitData.a < 0.0) {
        fragData0 = vec4(0.0);
        return;
    }
    float depth = sampleDepth(s_GbufferDepth, hitData.xy);
    vec2 currUV = getPreviousUV(vec3(hitData.xy * 2.0 - 1.0, depth));
    vec4 reflColor = vec4(texture(s_RasterColor, currUV).rgb,
        hitData.a);

#if 0
    // apply meh filter
    vec4 mean = vec4(0.0);
    vec4 m2 = vec4(0.0);
    float count = 0.0;
    vec4 nReflCol = vec4(0.0);

    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            vec2 nUV = v_texcoord0 + vec2(x, y) * ScreenSize.zw;
            vec4 nHitData = texture(s_InputTexture, nUV);
            if (nHitData.a > 0.0) {
                float nDepth = sampleDepth(s_GbufferDepth, nHitData.xy);
                vec2 nCurrUV = getPreviousUV(vec3(nHitData.xy * 2.0 - 1.0, nDepth));
                nReflCol = vec4(texture(s_RasterColor, nCurrUV).rgb, nHitData.a);
            }

            count += 1.0;
            vec4 delta = nReflCol - mean;
            mean += delta / count;
            m2 += delta * delta;
        }
    }

    vec2 prevUV = getPreviousUV(vec3(v_texcoord0 * 2.0 - 1.0, hitData.z));
    vec4 variance = sqrt(max(vec4(0.0), m2 / vec4(count - 1.0))) * 0.25;
    vec4 prevReflCol = clamp(
        texture(s_PreviousReflectionBuffer, prevUV * ViewportScale.zw),
        mean - variance, mean + variance);

    fragData0 = mix(prevReflCol, reflColor, SSRTemporalAccumulationParams.a);
#else
    fragData0 = reflColor;
#endif
#endif
}
#endif
