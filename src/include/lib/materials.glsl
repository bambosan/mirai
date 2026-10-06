#ifndef MATERIALS_INCLUDED
#define MATERIALS_INCLUDED

const int kInvalidPBRTexture       = 0xFFFF;
const int kPBRHasMaterialTexture   = 1;
const int kPBRHasSubsurfaceChannel = 2;
const int kPBRHasNormalTexture     = 4;
const int kPBRHasHeightMapTexture  = 8;
const int kPBRHasEncNormalTexture  = 16;

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
    if (metalness > subsurface) return 128.0 / 255.0 + 127.0 / 255.0 * metalness;
    return 127.0 / 255.0 - 127.0 / 255.0 * subsurface;
}

float unpackMetalness(float metalnessSubsurface) {
    return clamp(255.0 / 127.0 * (metalnessSubsurface - 128.0 / 255.0), 0.0, 1.0);
}

float unpackSubsurface(float metalnessSubsurface) {
    return clamp(255.0 / 127.0 * (127.0 / 255.0 - metalnessSubsurface), 0.0, 1.0);
}

vec3 calcNormalFromHeightmap(sampler2D heightmapTex, vec2 heightmapUV) {
    const float kHeightMapPixelEdgeWidth     = 0.08333333333333333;
    const float kRecipHeightMapDepth         = 0.25;
    const float kNudgePixelCentreDistEpsilon = 0.0625;
    const float kNudgeUvEpsilon              = 3.814697265625e-6;

    vec2 widthHeight = vec2(textureSize(heightmapTex, 0));
    vec2 pixelCoord = heightmapUV * widthHeight;

    vec2 nudgeSampleCoord = fract(pixelCoord);

    if (abs(nudgeSampleCoord.x - 0.5) < kNudgePixelCentreDistEpsilon)
        heightmapUV.x += (nudgeSampleCoord.x > 0.5) ? kNudgeUvEpsilon : -kNudgeUvEpsilon;
    if (abs(nudgeSampleCoord.y - 0.5) < kNudgePixelCentreDistEpsilon)
        heightmapUV.y += (nudgeSampleCoord.y > 0.5) ? kNudgeUvEpsilon : -kNudgeUvEpsilon;

    vec4 heightSamples = textureGather(heightmapTex, heightmapUV, 0);
    vec2 subPixelCoord = fract(pixelCoord + 0.5);

    vec3 tNormal = vec3(0.0, 0.0, 1.0);

    vec2 axisSample = (subPixelCoord.y > 0.5) ? heightSamples.xy : heightSamples.wz;
    ivec2 axisSampleIdx = ivec2(clamp(
        vec2(subPixelCoord.x - kHeightMapPixelEdgeWidth,
            subPixelCoord.x + kHeightMapPixelEdgeWidth) * 2.0, 0.0, 1.0));
    tNormal.x = axisSample[axisSampleIdx.x] - axisSample[axisSampleIdx.y];

    axisSample = (subPixelCoord.x > 0.5) ? heightSamples.zy : heightSamples.wx;
    axisSampleIdx = ivec2(clamp(
        vec2(subPixelCoord.y - kHeightMapPixelEdgeWidth,
            subPixelCoord.y + kHeightMapPixelEdgeWidth) * 2.0, 0.0, 1.0));
    tNormal.y = axisSample[axisSampleIdx.x] - axisSample[axisSampleIdx.y];

    tNormal.z = kRecipHeightMapDepth;
    tNormal = normalize(tNormal);

    return tNormal;
}

vec3 calcNormalFromEncTexture(sampler2D matTexture, vec4 texel, vec2 normalUV) {
    const float kHeightMapPixelEdgeWidth = 0.083333335816860198974609375;
    const float kRecipHeightMapDepth     = 0.25;
    const float kHeightMapFlattenEpsilon = 0.005;

    vec2 texelFrac = fract(normalUV * vec2(textureSize(matTexture, 0)));

    vec3 tNormal = vec3(0.0, 0.0, 1.0);
    tNormal.x = step(1.0 - kHeightMapPixelEdgeWidth, texelFrac.x) * (texel.g * 2.0 - 1.0)
        + step(texelFrac.x, kHeightMapPixelEdgeWidth) * (1.0 - texel.a * 2.0);
    tNormal.y = step(1.0 - kHeightMapPixelEdgeWidth, texelFrac.y) * (texel.b * 2.0 - 1.0)
        + step(texelFrac.y, kHeightMapPixelEdgeWidth) * (1.0 - texel.r * 2.0);
    tNormal.x = step(kHeightMapFlattenEpsilon, abs(tNormal.x)) * tNormal.x;
    tNormal.y = step(kHeightMapFlattenEpsilon, abs(tNormal.y)) * tNormal.y;
    tNormal.z = kRecipHeightMapDepth;
    tNormal = normalize(tNormal);

    return tNormal;
}

#if defined(MATERIAL_ITEM_IN_HAND_FORWARD_PBR_TEXTURED) \
    || defined(MATERIAL_ITEM_IN_HAND_PREPASS_TEXTURED) \
    || defined(MATERIAL_RENDERCHUNK_FORWARD_PBR) \
    || defined(MATERIAL_RENDERCHUNK_PREPASS) \
    || defined(MATERIAL_TEXTURE_SHIFT_RENDERCHUNK_PREPASS) \
    || defined(MATERIAL_SINGLE_BLOCK_FORWARD_PBR) \
    || defined(MATERIAL_SINGLE_BLOCK_PREPASS)

struct PBRTextureData {
    float colourToMaterialUvScale0;
    float colourToMaterialUvScale1;
    float colourToMaterialUvBias0;
    float colourToMaterialUvBias1;
    float colourToNormalUvScale0;
    float colourToNormalUvScale1;
    float colourToNormalUvBias0;
    float colourToNormalUvBias1;
    int flags;
    float uniformRoughness;
    float uniformEmissive;
    float uniformMetalness;
    float uniformSubsurface;
    float maxMipColour;
    float maxMipMer;
    float maxMipNormal;
};

BUFFER_RO(s_PBRData, PBRTextureData, s_PBRData1);

void texturePBRMaterials(
    sampler2D matTexture,
    int pbrTextureId,
    vec2 uv,
    vec3 tangent,
    vec3 bitangent,
    inout vec3 normal,
    inout vec4 mers
) {
    if (pbrTextureId == kInvalidPBRTexture) return;

    PBRTextureData pbrTextureData = s_PBRData1._data[pbrTextureId];

    mers = vec4(pbrTextureData.uniformMetalness, pbrTextureData.uniformEmissive,
        pbrTextureData.uniformRoughness, pbrTextureData.uniformSubsurface);

    vec2 materialUVScale = vec2(pbrTextureData.colourToMaterialUvScale0,
        pbrTextureData.colourToMaterialUvScale1);
    vec2 materialUVBias  = vec2(pbrTextureData.colourToMaterialUvBias0,
        pbrTextureData.colourToMaterialUvBias1);

    if ((pbrTextureData.flags & kPBRHasMaterialTexture) == kPBRHasMaterialTexture) {
        vec4 mersTex = texture(matTexture, uv * materialUVScale + materialUVBias);
        mers.rgb = mersTex.rgb;
        if ((pbrTextureData.flags & kPBRHasSubsurfaceChannel) == kPBRHasSubsurfaceChannel)
            mers.a = mersTex.a;
    }

    vec3 tNormal = vec3(0.0, 0.0, 1.0);

    vec2 normalUVScale = vec2(pbrTextureData.colourToNormalUvScale0,
        pbrTextureData.colourToNormalUvScale1);
    vec2 normalUVBias  = vec2(pbrTextureData.colourToNormalUvBias0,
        pbrTextureData.colourToNormalUvBias1);
    vec2 normalUV = uv * normalUVScale + normalUVBias;

    float mipFade = clamp(2.0 - min(
        pbrTextureData.maxMipNormal - pbrTextureData.maxMipColour,
        pbrTextureData.maxMipNormal
    ), 0.0, 1.0);

    if ((pbrTextureData.flags & kPBRHasNormalTexture) == kPBRHasNormalTexture) {
        tNormal = texture(matTexture, normalUV).rgb * 2.0 - 1.0;
    } else if ((pbrTextureData.flags & kPBRHasHeightMapTexture) == kPBRHasHeightMapTexture) {
        tNormal = calcNormalFromHeightmap(matTexture, normalUV);
        tNormal.xy *= mipFade;
    } else if ((pbrTextureData.flags & kPBRHasEncNormalTexture) == kPBRHasEncNormalTexture) {
        vec4 normalTex = textureLod(matTexture, normalUV, 0.0);
        if (normalTex.r == normalTex.g && normalTex.g == normalTex.b)
            tNormal = calcNormalFromHeightmap(matTexture, normalUV);
        else
            tNormal = calcNormalFromEncTexture(matTexture, normalTex, normalUV);
        tNormal.xy *= mipFade;
    }

    mat3 tbn = mat3(normalize(tangent), normalize(bitangent), normal);
    normal = tbn * tNormal;
}

#endif

#if defined(MATERIAL_ACTOR_FORWARD_PBR) \
    || defined(MATERIAL_ACTOR_GLINT_FORWARD_PBR) \
    || defined(MATERIAL_ACTOR_MULTI_TEXTURE_FORWARD_PBR) \
    || defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR) \
    || defined(MATERIAL_ACTOR_PATTERN_GLINT_FORWARD_PBR) \
    || defined(MATERIAL_ACTOR_TINT_FORWARD_PBR) \
    || defined(MATERIAL_ACTOR_PREPASS) \
    || defined(MATERIAL_ACTOR_GLINT_PREPASS) \
    || defined(MATERIAL_ACTOR_MULTI_TEXTURE_PREPASS) \
    || defined(MATERIAL_ACTOR_PATTERN_PREPASS) \
    || defined(MATERIAL_ACTOR_PATTERN_GLINT_PREPASS) \
    || defined(MATERIAL_ACTOR_TINT_PREPASS)

uniform vec4 PBRTextureFlags;
uniform vec4 MetalnessUniform;
uniform vec4 EmissiveUniform;
uniform vec4 RoughnessUniform;
uniform vec4 SubsurfaceUniform;

SAMPLER2D(s_MERSTexture);
SAMPLER2D(s_NormalTexture);

void texturePBRMaterials(
    vec2 uv,
    vec3 tangent,
    vec3 bitangent,
    inout vec3 normal,
    inout vec4 mers
) {
    mers = vec4(MetalnessUniform.r, EmissiveUniform.r, RoughnessUniform.r, SubsurfaceUniform.r);

    int pbrTextureFlags = int(PBRTextureFlags.r);

    if ((pbrTextureFlags & kPBRHasMaterialTexture) == kPBRHasMaterialTexture) {
        vec4 mersTex = texture(s_MERSTexture, uv);
        mers.rgb = mersTex.rgb;
        if ((pbrTextureFlags & kPBRHasSubsurfaceChannel) == kPBRHasSubsurfaceChannel)
            mers.a = mersTex.a;
    }

    vec3 tNormal = vec3(0.0, 0.0, 1.0);

    if ((pbrTextureFlags & kPBRHasNormalTexture) == kPBRHasNormalTexture) {
        tNormal = texture(s_NormalTexture, uv).rgb * 2.0 - 1.0;
    } else if ((pbrTextureFlags & kPBRHasHeightMapTexture) == kPBRHasHeightMapTexture) {
        tNormal = calcNormalFromHeightmap(s_NormalTexture, uv);
    } else if ((pbrTextureFlags & kPBRHasEncNormalTexture) == kPBRHasEncNormalTexture) {
        vec4 normalTex = textureLod(s_NormalTexture, uv, 0.0);
        if (normalTex.r == normalTex.g && normalTex.g == normalTex.b)
            tNormal = calcNormalFromHeightmap(s_NormalTexture, uv);
        else
            tNormal = calcNormalFromEncTexture(s_NormalTexture, normalTex, uv);
    }

    mat3 tbn = mat3(normalize(tangent), normalize(bitangent), normal);
    normal = tbn * tNormal;
}

#endif

#if defined(MATERIAL_ACTOR_BANNER_FORWARD_PBR) \
    || defined(MATERIAL_ACTOR_BANNER_PREPASS)

uniform vec4 BannerBasePBRTextureData[4];

void texturePBRMaterials(
    sampler2D matTexture,
    vec2 uv,
    vec3 tangent,
    vec3 bitangent,
    inout vec3 normal,
    inout vec4 mers
) {
    int pbrTextureId = int(BannerBasePBRTextureData[2].r);

    mers = vec4(BannerBasePBRTextureData[2].abg, BannerBasePBRTextureData[3].r);

    vec2 materialUVScale = vec2(BannerBasePBRTextureData[0].x, BannerBasePBRTextureData[0].y);
    vec2 materialUVBias = vec2(BannerBasePBRTextureData[0].z, BannerBasePBRTextureData[0].w);

    if ((pbrTextureId & kPBRHasMaterialTexture) == kPBRHasMaterialTexture) {
        vec4 mersTex = texture(matTexture, uv * materialUVScale + materialUVBias);
        mers.rgb = mersTex.rgb;
        if ((pbrTextureId & kPBRHasSubsurfaceChannel) == kPBRHasSubsurfaceChannel)
            mers.a = mersTex.a;
    }

    vec3 tNormal = vec3(0.0, 0.0, 1.0);

    vec2 normalUVScale = vec2(BannerBasePBRTextureData[1].x, BannerBasePBRTextureData[1].y);
    vec2 normalUVBias = vec2(BannerBasePBRTextureData[1].z, BannerBasePBRTextureData[1].w);
    vec2 normalUV = uv * normalUVScale + normalUVBias;

    float mipFade = clamp(2.0 - min(
        BannerBasePBRTextureData[3].w - BannerBasePBRTextureData[3].y,
        BannerBasePBRTextureData[3].w
    ), 0.0, 1.0);

    if ((pbrTextureId & kPBRHasNormalTexture) == kPBRHasNormalTexture) {
        tNormal = texture(matTexture, normalUV).rgb * 2.0 - 1.0;
    } else if ((pbrTextureId & kPBRHasHeightMapTexture) == kPBRHasHeightMapTexture) {
        tNormal = calcNormalFromHeightmap(matTexture, normalUV);
        tNormal.xy *= mipFade;
    } else if ((pbrTextureId & kPBRHasEncNormalTexture) == kPBRHasEncNormalTexture) {
        vec4 normalTex = textureLod(matTexture, normalUV, 0.0);
        if (normalTex.r == normalTex.g && normalTex.g == normalTex.b)
            tNormal = calcNormalFromHeightmap(matTexture, normalUV);
        else
            tNormal = calcNormalFromEncTexture(matTexture, normalTex, normalUV);
        tNormal.xy *= mipFade;
    }

    mat3 tbn = mat3(normalize(tangent), normalize(bitangent), normal);
    normal = tbn * tNormal;
}

#endif
#endif
