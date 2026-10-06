///////////////////////////////////////////////////////////
// VERTEX SHADER
///////////////////////////////////////////////////////////
#if SHADER_STAGE__VERTEX
uniform vec4 ViewportScale;

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
    v_texcoord0 = a_texcoord0 * ViewportScale.xy;
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
uniform mat4 u_view;
uniform mat4 u_proj;
uniform mat4 u_invProj;
uniform mat4 u_prevViewProj;
uniform mat4 u_invViewProj;

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
    if (CameraData.x < CameraData.y)
        return CameraData.x < depth && depth < CameraData.y;
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

float calcFadingValue(float roughness, float rayPercentage) {
    float fadeValueRay = smoothstep(1.0, 0.9, rayPercentage);
    float roughnessFadeDist = SSRRoughnessCutoffParams.x - SSRRoughnessCutoffParams.y;
    float roughnessLerpAlpha = (max(roughness, SSRRoughnessCutoffParams.y)
        - SSRRoughnessCutoffParams.y) / roughnessFadeDist;
    float fadeValueRoughness = mix(1.0, 0.0, roughnessLerpAlpha);
    float fadeValue = min(fadeValueRay, fadeValueRoughness);
    return fadeValue;
}

int calcStepsCount(vec3 rayStartSS, vec3 rayStepSS) {
    vec3 scTopLeftNearCorner = rayStartSS / rayStepSS;
    vec3 scBottomRightFarCorner = (vec3(1.0) - rayStartSS) / rayStepSS;
    vec3 lowestSC = vec3(
        rayStepSS.x < 0.0 ? abs(scTopLeftNearCorner.x) : scBottomRightFarCorner.x,
        rayStepSS.y < 0.0 ? abs(scTopLeftNearCorner.y) : scBottomRightFarCorner.y,
        rayStepSS.z < 0.0 ? abs(scTopLeftNearCorner.z) : scBottomRightFarCorner.z
    );
    float minStepsCount = min(min(lowestSC.x, lowestSC.y), lowestSC.z);
    int stepsCount = int(min(minStepsCount, SSRRayMarchingParams.x));
    return stepsCount;
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

        if (sceneLinearDepth <= rayLinearDepth
            && prevRayDepth <= (
                sceneLinearDepth + sceneLinearDepth * SSRFadingParamsAndThickness.a
            )) {
            foundIter = i;
            foundCoord = posSS;
            break;
        }

        prevRayDepth = rayLinearDepth;
    }

    return foundIter;
}

float doBinarySearch(
    int foundIter,
    vec3 rayStartSS,
    vec3 rayStepSS,
    inout vec3 foundCoord
) {
    float iterBeforeHit = float(foundIter - 1);
    float iterAfterHit = float(foundIter);
    float refinedIter = iterAfterHit;
    int bStepCount = int(SSRRayMarchingParams.w);

    for (int i = 0; i < bStepCount; i++) {
        float iterMid = (iterBeforeHit + iterAfterHit) * 0.5;
        vec3 posMid = rayStartSS + (rayStepSS * iterMid);
        float rayLinearDepth = projToLinearDepth(posMid.z);
        float sceneDepth = sampleDepth(s_GbufferDepth, posMid.xy);
        float sceneLinearDepth = projToLinearDepth(sceneDepth);

        if (rayLinearDepth > sceneLinearDepth) {
            iterAfterHit = iterMid;
            refinedIter = iterMid;
            foundCoord = posMid;
        } else {
            iterBeforeHit = iterMid;
        }
    }

    return refinedIter;
}

#if !SSR_RAY_MARCH_HZB_PASS
layout(location = 0) in vec2 v_texcoord0;
#endif
#if SSR_RAY_MARCH_PASS
layout(location = 1) in vec2 v_projPos;
#endif

out vec4 fragData0;

void main() {
#if SSR_RAY_MARCH_PASS
    vec2 stexcoord = (floor(v_texcoord0.xy * ScreenSize.xy) + 0.5) * ScreenSize.zw;

    uvec4 data16 = texelFetch(s_GbufferRoughness, ivec2(gl_FragCoord.xy), 0) & 0xFFFFu;
    float roughness = float(data16.r >> 8) / 255.0;
    if (roughness > SSRRoughnessCutoffParams.x) {
        fragData0 = vec4(0.0, 0.0, 0.0, -1.0);
        return;
    }

    float depth = sampleDepth(s_GbufferDepth, stexcoord);

    vec3 viewPos = projToView(vec3(v_projPos, depth), u_invProj);
    vec3 normal = octToNdirSnorm(texture(s_GbufferNormal, stexcoord).rg);
    vec3 viewNormal = (u_view * vec4(normal, 0.0)).xyz;

    vec3 reflectedView = reflect(normalize(viewPos), viewNormal);
    vec3 rayStartView = viewPos + viewNormal * SSRRayMarchingParams.z;
    vec3 rayEndView = rayStartView + reflectedView;

    if (!isDepthInCameraBounds(rayStartView.z)
        || !isDepthInCameraBounds(rayEndView.z)) {
        fragData0 = vec4(0.0, 0.0, 0.0, -1.0);
        return;
    }

    vec3 rayStartSS = viewToProj(rayStartView, u_proj);
    vec3 rayEndSS = viewToProj(rayEndView, u_proj);
    vec3 raySpanSS = rayEndSS - rayStartSS;
    vec3 rayStepSS = normalize(raySpanSS) / SSRRayMarchingParams.x;
    int stepsCount = calcStepsCount(rayStartSS, rayStepSS);
    vec3 foundCoord = vec3(0.0);

    int foundIter = doLinearSearch(rayStartSS, rayStepSS, stepsCount, foundCoord);
    if (foundIter < 1) {
        fragData0 = vec4(0.0, 0.0, 0.0, -1.0);
        return;
    }

    float refinedIter = doBinarySearch(foundIter, rayStartSS, rayStepSS, foundCoord);
    fragData0.rgb = foundCoord;

    float rayPercentage = refinedIter / float(stepsCount);
    fragData0.a = (foundCoord.x > 0.0 && foundCoord.x < 1.0
        && foundCoord.y > 0.0 && foundCoord.y < 1.0)
    ? calcFadingValue(roughness, rayPercentage) : 0.0;
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

#if 1
    // apply meh filter
    vec4 mean = vec4(0.0);
    vec4 m2 = vec4(0.0);
    float count = 0.0;

    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            vec2 nUV = v_texcoord0 + vec2(x, y) * ScreenSize.zw;
            vec4 nHitData = texture(s_InputTexture, nUV);
            float nDepth = sampleDepth(s_GbufferDepth, nHitData.xy);
            vec2 nCurrUV = getPreviousUV(vec3(nHitData.xy * 2.0 - 1.0, nDepth));
            vec4 nReflCol = vec4(texture(s_RasterColor, nCurrUV).rgb, nHitData.a);

            count += 1.0;
            vec4 delta = nReflCol - mean;
            mean += delta / count;
            m2 += delta * delta;
        }
    }

    vec2 prevUV = getPreviousUV(vec3(v_texcoord0 * 2.0 - 1.0, hitData.z));
    vec4 variance = sqrt(max(vec4(0.0), m2 / vec4(count - 1.0)));
    vec4 prevReflCol = texture(s_PreviousReflectionBuffer, prevUV * ViewportScale.zw);
    prevReflCol = clamp(
        prevReflCol,
        mean - variance * SSRTemporalAccumulationParams.y,
        mean + variance * SSRTemporalAccumulationParams.y
    );

    fragData0 = mix(prevReflCol, reflColor, SSRTemporalAccumulationParams.a);
#else
    fragData0 = reflColor;
#endif
#endif
}
#endif
