#ifndef ACTOR_UTIL_INCLUDE
#define ACTOR_UTIL_INCLUDE

// still have some bugs

vec2 applyUvAnimation(vec2 uv, vec4 uvAnimation) {
    uv = uvAnimation.xy + (uv * uvAnimation.zw);
    return uv;
}

vec2 calculateLayerUV(vec2 origUV, float offsets, float rotation, vec2 scale) {
    vec2 uv = origUV;
    uv -= 0.5;
    float rsin = sin(rotation);
    float rcos = cos(rotation);
    uv = mul(uv, mtxFromCols(vec2(rcos, -rsin), vec2(rsin, rcos)));
    uv.x += offsets;
    uv += 0.5;
    return uv * scale;
}

vec3 applyMultiColorChange(vec3 albedo, vec3 changeColor, vec3 multiplicativeTintColor) {
    vec2 colorMask = albedo.rg;
    albedo = colorMask.rrr * changeColor;
    albedo = mix(albedo, colorMask.ggg * multiplicativeTintColor.rgb, ceil(colorMask.g));
    return albedo;
}

#if defined(MATERIAL_ACTOR_FORWARD_PBR) || defined(MATERIAL_ACTOR_PATTERN_FORWARD_PBR)

vec4 applyChangeColor(vec4 albedo, vec4 changeColor, vec3 multiplicativeTintColor, float shouldChangeAlpha) {
#if CHANGE_COLOR__MULTI
    albedo.rgb = applyMultiColorChange(albedo.rgb, changeColor.rgb, multiplicativeTintColor);
#endif
#if CHANGE_COLOR__ON
    albedo.rgb = mix(albedo.rgb, albedo.rgb * changeColor.rgb, albedo.a);
    albedo.a *= changeColor.a;
#endif
    albedo.a = max(shouldChangeAlpha, albedo.a);
    return albedo;
}

bool shouldDiscard(vec3 albedo, float alpha, float epsilon) {
    bool result = false;
#if EMISSIVE__EMISSIVE
    result = dot(vec4(albedo, alpha), vec4_splat(1.0)) < epsilon;
#endif
#if EMISSIVE__EMISSIVE_ONLY
    result = alpha < epsilon || alpha > 1.0 - epsilon;
#endif
#if EMISSIVE__OFF && !CHANGE_COLOR__OFF
    result = alpha < epsilon;
#endif
#if CHANGE_COLOR__OFF && EMISSIVE__OFF
    result = alpha < 0.5;
#endif
    return result;
}

#else

vec4 applyChangeColor(vec4 albedo, vec4 changeColor, vec3 multiplicativeTintColor, float shouldChangeAlpha) {
#if CHANGE_COLOR__MULTI
    albedo.rgb = applyMultiColorChange(albedo.rgb, changeColor.rgb, multiplicativeTintColor);
#endif
    albedo.a = max(shouldChangeAlpha, albedo.a);
    return albedo;
}

bool shouldDiscard(vec3 albedo, float alpha, float epsilon) {
    bool result = false;
#if CHANGE_COLOR__MULTI
    result = alpha < epsilon;
#endif
#if CHANGE_COLOR__OFF
    result = alpha < 0.5;
#endif
    return result;
}

#endif

vec4 getActorAlbedoNoColorChange(vec4 matColor, highp sampler2D matTexture, highp sampler2D matTexture1, vec2 uv) {
    vec4 albedo = texture2D(matTexture, uv) * matColor;
#if MASKED_MULTITEXTURE__ON
    vec4 tex1 = texture2D(matTexture1, uv);
    float maskedTexture = float((tex1.r + tex1.g + tex1.b) * (1.0 - tex1.a) > 0.0);
    albedo = mix(tex1, albedo, maskedTexture);
#endif
    return albedo;
}

vec4 getBannerAlbedo(vec4 color, highp sampler2D matTexture, vec2 texcoord0, vec2 texcoord1) {
    vec4 albedo = texture2D(matTexture, texcoord0);
#if TINTING__ENABLED
    vec4 albedo2 = texture2D(matTexture, texcoord1);
    albedo.a = mix(albedo2.r * albedo2.a, albedo2.a, color.a);
    albedo.rgb *= color.rgb;
#endif
    return albedo;
}

vec3 applyGlint(vec3 albedo, vec4 layerUV, highp sampler2D glintTexture, vec4 glintColor) {
    vec4 tex1 = texture2D(glintTexture, fract(layerUV.xy)) * glintColor;
    vec4 tex2 = texture2D(glintTexture, fract(layerUV.zw)) * glintColor;
    vec4 glint = tex1 + tex2;
    albedo += glint.rgb * glint.rgb;
    return albedo;
}

vec4 applySecondTextureColor(vec4 albedo, vec4 changeColor, highp sampler2D matTexture2, vec2 uv, float epsilon) {
    vec4 tex2 = texture2D(matTexture2, uv);
#if COLOR_SECOND_TEXTURE__OFF
    albedo.rgb = mix(albedo.rgb, tex2.rgb, tex2.a);
#endif
#if COLOR_SECOND_TEXTURE__ON
    if (tex2.a > epsilon) albedo.rgb = mix(tex2.rgb, tex2.rgb * changeColor.rgb, tex2.a);
#endif
    return albedo;
}

vec4 applyMultitextureAlbedo(vec4 albedo, vec4 changeColor, highp sampler2D matTexture1, highp sampler2D matTexture2, vec2 uv, float epsilon, out float tex1Alpha) {
    vec4 tex1 = texture2D(matTexture1, uv);
    tex1Alpha = tex1.a;
    albedo.rgb = mix(albedo.rgb, tex1.rgb, tex1.a);
    albedo = applySecondTextureColor(albedo, changeColor, matTexture2, uv, epsilon);
    return albedo;
}

vec4 applySecondColorTint(vec4 albedo, vec3 multiplicativeTintColor, highp sampler2D matTexture1, vec2 uv, out float tintAlpha) {
    vec4 tintTex = texture2D(matTexture1, uv);
    tintAlpha = tintTex.a;
    tintTex.rgb *= multiplicativeTintColor;
    albedo.rgb = mix(albedo.rgb, tintTex.rgb, tintTex.a);
    return albedo;
}

#endif //ACTOR_UTIL_INCLUDE
