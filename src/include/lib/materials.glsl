#ifndef MATERIALS_INCLUDE
#define MATERIALS_INCLUDE

CONST(float) kHeightMapPixelEdgeWidth = 0.08333333333333333;
CONST(float) kHeightMapDepth = 4.0;
CONST(float) kRecipHeightMapDepth = 0.25;
CONST(float) kNudgePixelCentreDistEpsilon = 0.0625;
CONST(float) kNudgeUvEpsilon = 3.814697265625e-06;

CONST(int) kInvalidPBRTextureHandle = 0xffff;
CONST(int) kPBRTextureDataFlagHasMaterialTexture = 1;
CONST(int) kPBRTextureDataFlagHasSubsurfaceChannel = 2;
CONST(int) kPBRTextureDataFlagHasNormalTexture = 4;
CONST(int) kPBRTextureDataFlagHasHeightMapTexture = 8;

vec2 octWrap(vec2 v) {
    return (1.0 - abs(v.yx)) * ((2.0 * step(0.0, v)) - 1.0);
}

vec2 ndirToOctSnorm(vec3 n) {
    vec2 p = n.xy * (1.0 / (abs(n.x) + abs(n.y) + abs(n.z)));
    p = (n.z < 0.0) ? octWrap(p) : p;
    return p;
}

vec3 octToNdirSnorm(vec2 p) {
    vec3 n = vec3(p.xy, 1.0 - abs(p.x) - abs(p.y));
    n.xy = (n.z < 0.0) ? octWrap(n.xy) : n.xy;
    return normalize(n);
}

float packMetalnessSubsurface(float metalness, float subsurface) {
    if (metalness > subsurface) return 0.5019607843137255 + 0.4980392156862745 * metalness;
    return 0.4980392156862745 - 0.4980392156862745 * subsurface;
}

float unpackMetalness(float metalnessSubsurface) {
    return clamp(2.0078740157480315 * (metalnessSubsurface - 0.5019607843137255), 0.0, 1.0);
}

float unpackSubsurface(float metalnessSubsurface) {
    return clamp(2.0078740157480315 * (0.4980392156862745 - metalnessSubsurface), 0.0, 1.0);
}

vec3 calculateTangentNormalFromHeightmap(highp sampler2D heightmapTexture, vec2 heightmapUV, float mipLevel) {
    vec3 tangentNormal = vec3(0.0, 0.0, 1.0);
    float fadeForLowerMips = linearstep(2.0, 1.0, mipLevel);

    if (fadeForLowerMips > 0.0) {
        vec2 widthHeight = vec2(textureSize(heightmapTexture, 0));
        vec2 pixelCoord = heightmapUV * widthHeight;
        vec2 nudgeSampleCoord = fract(pixelCoord);

        if (abs(nudgeSampleCoord.x - 0.5) < kNudgePixelCentreDistEpsilon) {
            heightmapUV.x += (nudgeSampleCoord.x > 0.5) ? kNudgeUvEpsilon : -kNudgeUvEpsilon;
        }

        if (abs(nudgeSampleCoord.y - 0.5) < kNudgePixelCentreDistEpsilon) {
            heightmapUV.y += (nudgeSampleCoord.y > 0.5) ? kNudgeUvEpsilon : -kNudgeUvEpsilon;
        }

        vec4 heightSamples = textureGather(heightmapTexture, heightmapUV, 0);
        vec2 subPixelCoord = fract(pixelCoord + 0.5);

        vec2 axisSamplePair = (subPixelCoord.y > 0.5) ? heightSamples.xy : heightSamples.wz;
        ivec2 axisSampleIndices = ivec2(clamp(vec2(subPixelCoord.x - kHeightMapPixelEdgeWidth, subPixelCoord.x + kHeightMapPixelEdgeWidth) * 2.0, 0.0, 1.0));
        tangentNormal.x = (axisSamplePair[axisSampleIndices.x] - axisSamplePair[axisSampleIndices.y]);

        axisSamplePair = (subPixelCoord.x > 0.5) ? heightSamples.zy : heightSamples.wx;
        axisSampleIndices = ivec2(clamp(vec2(subPixelCoord.y - kHeightMapPixelEdgeWidth, subPixelCoord.y + kHeightMapPixelEdgeWidth) * 2.0, 0.0, 1.0));
        tangentNormal.y = (axisSamplePair[axisSampleIndices.x] - axisSamplePair[axisSampleIndices.y]);

        tangentNormal.z = kRecipHeightMapDepth;
        tangentNormal = normalize(tangentNormal);
        tangentNormal.xy *= fadeForLowerMips;
    }

    return tangentNormal;
}

#if defined(MATERIAL_ITEM_IN_HAND_FORWARD_PBR_TEXTURED) || \
defined(MATERIAL_RENDERCHUNK_FORWARD_PBR) || \
defined(MATERIAL_RENDERCHUNK_PREPASS) || \
defined(MATERIAL_MESH_FALLBACK_MOVING_BLOCK_FORWARD_PBR)

struct PBRTextureData {
    highp float colourToMaterialUvScale0;
    highp float colourToMaterialUvScale1;
    highp float colourToMaterialUvBias0;
    highp float colourToMaterialUvBias1;
    highp float colourToNormalUvScale0;
    highp float colourToNormalUvScale1;
    highp float colourToNormalUvBias0;
    highp float colourToNormalUvBias1;
    int flags;
    highp float uniformRoughness;
    highp float uniformEmissive;
    highp float uniformMetalness;
    highp float uniformSubsurface;
    highp float maxMipColour;
    highp float maxMipMer;
    highp float maxMipNormal;
};

BUFFER_RO_AUTOREG(s_PBRData, PBRTextureData);

void getTexturePBRMaterials(
    highp sampler2D matTexture,
    int pbrTextureId,
    vec2 uv,
    vec3 tangent,
    vec3 bitangent,
    inout vec3 normal,
    inout vec4 mers
) {
    if (pbrTextureId == kInvalidPBRTextureHandle) return;

    PBRTextureData pbrTextureData = s_PBRData[pbrTextureId];

    mers = vec4(pbrTextureData.uniformMetalness, pbrTextureData.uniformEmissive, pbrTextureData.uniformRoughness, pbrTextureData.uniformSubsurface);

    if ((pbrTextureData.flags & kPBRTextureDataFlagHasMaterialTexture) == kPBRTextureDataFlagHasMaterialTexture) {
        vec2 materialUVScale = vec2(pbrTextureData.colourToMaterialUvScale0, pbrTextureData.colourToMaterialUvScale1);
        vec2 materialUVBias = vec2(pbrTextureData.colourToMaterialUvBias0, pbrTextureData.colourToMaterialUvBias1);

        vec4 mersTex = texture2D(matTexture, uv * materialUVScale + materialUVBias);
        mers.rgb = mersTex.rgb;
        if ((pbrTextureData.flags & kPBRTextureDataFlagHasSubsurfaceChannel) == kPBRTextureDataFlagHasSubsurfaceChannel) mers.a = mersTex.a;
    }

    vec3 tNormal = vec3(0.0, 0.0, 1.0);
    bool hasNormal = (pbrTextureData.flags & kPBRTextureDataFlagHasNormalTexture) == kPBRTextureDataFlagHasNormalTexture;
    bool hasHeightmap = (pbrTextureData.flags & kPBRTextureDataFlagHasHeightMapTexture) == kPBRTextureDataFlagHasHeightMapTexture;

    if (hasNormal || hasHeightmap) {
        vec2 normalUVScale = vec2(pbrTextureData.colourToNormalUvScale0, pbrTextureData.colourToNormalUvScale1);
        vec2 normalUVBias = vec2(pbrTextureData.colourToNormalUvBias0, pbrTextureData.colourToNormalUvBias1);

        if (hasNormal) {
            tNormal = texture2D(matTexture, uv * normalUVScale + normalUVBias).rgb * 2.0 - 1.0;
        } else if (hasHeightmap) {
            float normalMipLevel = min(pbrTextureData.maxMipNormal - pbrTextureData.maxMipColour, pbrTextureData.maxMipNormal);
            tNormal = calculateTangentNormalFromHeightmap(matTexture, uv * normalUVScale + normalUVBias, normalMipLevel);
        }
    }

    mat3 tbn = mtxFromCols(normalize(tangent), normalize(bitangent), normal);
    normal = mul(tbn, tNormal);
}

#endif

#if (defined(MATERIAL_ACTOR_BANNER_FORWARD_PBR) && FORWARD_PBR_ALPHA_TEST_PASS) || \
defined(MATERIAL_ACTOR_FORWARD_PBR) || \
defined(MATERIAL_ACTOR_GLINT_FORWARD_PBR) || \
defined(MATERIAL_ACTOR_MULTI_TEXTURE_FORWARD_PBR) || \
defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR) || \
defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR) || \
defined(MATERIAL_ACTOR_TINT_FORWARD_PBR)

uniform highp vec4 PBRTextureFlags;
uniform highp vec4 MetalnessUniform;
uniform highp vec4 EmissiveUniform;
uniform highp vec4 RoughnessUniform;
uniform highp vec4 SubsurfaceUniform;

SAMPLER2D_HIGHP_AUTOREG(s_MERSTexture);
SAMPLER2D_HIGHP_AUTOREG(s_NormalTexture);

void getTexturePBRMaterials(
    vec2 uv,
    vec3 tangent,
    vec3 bitangent,
    inout vec3 normal,
    inout vec4 mers
) {
    mers = vec4(MetalnessUniform.r, EmissiveUniform.r, RoughnessUniform.r, SubsurfaceUniform.r);

    int pbrTextureFlags = int(PBRTextureFlags.r);

    if ((pbrTextureFlags & kPBRTextureDataFlagHasMaterialTexture) == kPBRTextureDataFlagHasMaterialTexture) {
        vec4 mersTex = texture2D(s_MERSTexture, uv);
        mers.rgb = mersTex.rgb;
        if ((pbrTextureFlags & kPBRTextureDataFlagHasSubsurfaceChannel) == kPBRTextureDataFlagHasSubsurfaceChannel) mers.a = mersTex.a;
    }

    vec3 tNormal = vec3(0.0, 0.0, 1.0);

    if ((pbrTextureFlags & kPBRTextureDataFlagHasNormalTexture) == kPBRTextureDataFlagHasNormalTexture) {
        tNormal = texture2D(s_NormalTexture, uv).rgb * 2.0 - 1.0;
    } else if ((pbrTextureFlags & kPBRTextureDataFlagHasHeightMapTexture) == kPBRTextureDataFlagHasHeightMapTexture) {
        tNormal = calculateTangentNormalFromHeightmap(s_NormalTexture, uv, 0.0);
    }

    mat3 tbn = mtxFromCols(normalize(tangent), normalize(bitangent), normal);
    normal = mul(tbn, tNormal);
}

#endif

#if defined(MATERIAL_ACTOR_BANNER_FORWARD_PBR) && (FORWARD_PBR_OPAQUE_PASS || FORWARD_PBR_TRANSPARENT_PASS)

uniform highp vec4 BannerBasePBRTextureData[4];

void getTexturePBRMaterials(
    highp sampler2D matTexture,
    vec2 uv,
    vec3 tangent,
    vec3 bitangent,
    inout vec3 normal,
    inout vec4 mers
) {
    int pbrTextureId = int(BannerBasePBRTextureData[2].r);

    mers = vec4(BannerBasePBRTextureData[2].abg, BannerBasePBRTextureData[3].r);

    if ((pbrTextureId & kPBRTextureDataFlagHasMaterialTexture) == kPBRTextureDataFlagHasMaterialTexture) {
        vec2 materialUVScale = vec2(BannerBasePBRTextureData[0].x, BannerBasePBRTextureData[0].y);
        vec2 materialUVBias = vec2(BannerBasePBRTextureData[0].z, BannerBasePBRTextureData[0].w);

        vec4 mersTex = texture2D(matTexture, uv * materialUVScale + materialUVBias);
        mers.rgb = mersTex.rgb;
        if ((pbrTextureId & kPBRTextureDataFlagHasSubsurfaceChannel) == kPBRTextureDataFlagHasSubsurfaceChannel) mers.a = mersTex.a;
    }

    vec3 tNormal = vec3(0.0, 0.0, 1.0);
    bool hasNormal = (pbrTextureId & kPBRTextureDataFlagHasNormalTexture) == kPBRTextureDataFlagHasNormalTexture;
    bool hasHeightmap = (pbrTextureId & kPBRTextureDataFlagHasHeightMapTexture) == kPBRTextureDataFlagHasHeightMapTexture;

    if (hasNormal || hasHeightmap) {
        vec2 normalUVScale = vec2(BannerBasePBRTextureData[1].x, BannerBasePBRTextureData[1].y);
        vec2 normalUVBias = vec2(BannerBasePBRTextureData[1].z, BannerBasePBRTextureData[1].w);

        if (hasNormal) {
            tNormal = texture2D(matTexture, uv * normalUVScale + normalUVBias).rgb * 2.0 - 1.0;
        } else if (hasHeightmap) {
            float normalMipLevel = min(BannerBasePBRTextureData[3].w - BannerBasePBRTextureData[3].y, BannerBasePBRTextureData[3].w);
            tNormal = calculateTangentNormalFromHeightmap(matTexture, uv * normalUVScale + normalUVBias, normalMipLevel);
        }
    }

    mat3 tbn = mtxFromCols(normalize(tangent), normalize(bitangent), normal);
    normal = mul(tbn, tNormal);
}

#endif

#endif //MATERIALS_INCLUDE
