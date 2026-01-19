#include "./lib/taau_util.glsl"

#if BGFX_SHADER_TYPE_VERTEX
void main() {
#if INSTANCING__ON
    vec3 worldPos = mul(mtxFromCols(i_data1, i_data2, i_data3, vec4(0.0, 0.0, 0.0, 1.0)), vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = mul(u_model[0], vec4(a_position, 1.0)).xyz;
#endif

#if RENDER_AS_BILLBOARDS__ON
    worldPos += vec3_splat(0.5);
    vec3 forward = normalize(-worldPos);
    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
    vec3 up = cross(forward, right);
    vec3 offsets = a_color0.xyz;
    worldPos -= up * (offsets.z - 0.5) + right * (offsets.x - 0.5);
#endif

    gl_Position = mul(u_viewProj, vec4(worldPos, 1.0));

#if !DEPTH_ONLY_PASS
    uint data16 = uint(round(a_texcoord1.y * 65535.0));
    v_lightmapUV = vec2(uvec2(data16 >> 4u, data16) & uvec2(15u, 15u)) / 15.0;
    v_normal = mul(u_model[0], vec4(a_normal.xyz, 0.0)).xyz;
    v_tangent = mul(u_model[0], vec4(a_tangent.xyz, 0.0)).xyz;
    v_bitangent = mul(u_model[0], vec4(cross(a_normal.xyz, a_tangent.xyz) * a_tangent.w, 0.0)).xyz;
    v_worldPos = worldPos;
#endif
}
#endif

#if BGFX_SHADER_TYPE_FRAGMENT

uniform highp vec4 WorldOrigin;
uniform highp vec4 Time;

#include "./lib/common.glsl"
#include "./lib/materials.glsl"
#include "./lib/water_wave.glsl"

void main() {
#if DEPTH_ONLY_PASS
    gl_FragColor = vec4_splat(1.0);
#elif DEPTH_AND_NORMAL_PASS
    gl_FragData[0] = vec4_splat(0.0);
#else
    gl_FragData[0] = vec4_splat(0.0);

    vec3 normal = gl_FrontFacing ? -v_normal : v_normal;
    normal = normalize(normal);
    mat3 tbn = mtxFromCols(normalize(v_tangent), normalize(v_bitangent), normal);

    vec2 waterPos = (v_worldPos.xz - WorldOrigin.xz) * 0.15;
    vec3 waterNormal = getWaterNormal(waterPos, Time.x);
    waterNormal = mul(tbn, waterNormal);
    waterNormal = mix(normal, waterNormal, saturate(exp(-length(v_worldPos.xz) * 0.01)));

    gl_FragData[1].xy = ndirToOctSnorm(waterNormal);
    gl_FragData[1].zw = calculateMotionVector(v_worldPos, v_worldPos - u_prevWorldPosOffset.xyz);
    gl_FragData[2] = vec4(0.0, v_lightmapUV, 0.05);
#endif
}
#endif
