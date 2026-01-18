#include "./lib/taau_util.glsl"
#include "./lib/common.glsl"

#if BGFX_SHADER_TYPE_VERTEX

void main() {
#if INSTANCING__ON
    vec3 worldPos = mul(mtxFromCols(i_data1, i_data2, i_data3, vec4(0.0, 0.0, 0.0, 1.0)), vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = mul(u_model[0], vec4(a_position, 1.0)).xyz;
#endif

#if RENDER_AS_BILLBOARDS__ON
    vec4 color = vec4_splat(1.0);
    worldPos += vec3_splat(0.5);
    vec3 forward = normalize(-worldPos);
    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
    vec3 up = cross(forward, right);
    vec3 offsets = a_color0.xyz;
    worldPos -= up * (offsets.z - 0.5) + right * (offsets.x - 0.5);
#else
    vec4 color = a_color0;
#endif

#if GEOMETRY_PREPASS_PASS || GEOMETRY_PREPASS_ALPHA_TEST_PASS
    gl_Position = jitterVertexPosition(worldPos);
#else
    gl_Position = mul(u_viewProj, vec4(worldPos, 1.0));
#endif

    v_texcoord0 = a_texcoord0;

#if !DEPTH_ONLY_PASS && !DEPTH_ONLY_OPAQUE_PASS
#if BGFX_SHADER_LANGUAGE_GLSL
    v_lightmapUV = a_texcoord1; //fidex by mtbinloader2!
#else
    uint data16 = uint(round(a_texcoord1.y * 65535.0));
    v_lightmapUV = vec2(uvec2(data16 >> 4u, data16) & uvec2(15u, 15u)) / 15.0;
#endif
    v_pbrTextureId = a_texcoord4 & 0xffff;
    v_normal = mul(u_model[0], vec4(a_normal.xyz, 0.0)).xyz;
    v_tangent = mul(u_model[0], vec4(a_tangent.xyz, 0.0)).xyz;
    v_bitangent = mul(u_model[0], vec4(cross(a_normal.xyz, a_tangent.xyz) * a_tangent.w, 0.0)).xyz;
    v_worldPos = worldPos;
    v_color0 = color;
#endif
}
#endif

#if BGFX_SHADER_TYPE_FRAGMENT
SAMPLER2D_HIGHP_AUTOREG(s_MatTexture);
SAMPLER2D_HIGHP_AUTOREG(s_SeasonsTexture);

#include "./lib/materials.glsl"

void main() {
#if DEPTH_ONLY_PASS
    if (texture2D(s_MatTexture, v_texcoord0).a < 0.5) discard;
    gl_FragData[0] = vec4_splat(1.0);
    gl_FragData[1] = vec4_splat(0.0);
    gl_FragData[2] = vec4_splat(0.0);
#elif DEPTH_ONLY_OPAQUE_PASS
    gl_FragData[0] = vec4_splat(1.0);
    gl_FragData[1] = vec4_splat(0.0);
    gl_FragData[2] = vec4_splat(0.0);
#else
    vec4 albedo = texture2D(s_MatTexture, v_texcoord0);
#if GEOMETRY_PREPASS_ALPHA_TEST_PASS
    if (albedo.a < 0.5) discard;
#endif
#if SEASONS__ON
    albedo.rgb *= mix(vec3_splat(1.0), texture2D(s_SeasonsTexture, v_color0.rg).rgb * 2.0, v_color0.b);
#else
    albedo.rgb *= v_color0.rgb;
#endif

    vec3 normal = gl_FrontFacing ? -v_normal : v_normal;
    normal = normalize(normal);
    vec4 mers = vec4(0.0, 0.0, 1.0, 0.0);
    getTexturePBRMaterials(s_MatTexture, v_pbrTextureId, v_texcoord0, v_tangent, v_bitangent, normal, mers);

    gl_FragData[0] = vec4(albedo.rgb, packMetalnessSubsurface(mers.r, mers.a));
    gl_FragData[1].xy = ndirToOctSnorm(normal);
    gl_FragData[1].zw = calculateMotionVector(v_worldPos, v_worldPos - u_prevWorldPosOffset.xyz);
    gl_FragData[2] = vec4(mers.g, v_lightmapUV, mers.b);
#endif
}

#endif //BGFX_SHADER_TYPE_FRAGMENT
