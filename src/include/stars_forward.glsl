#if BGFX_SHADER_TYPE_VERTEX
void main() {
#if INSTANCING__ON
    vec3 worldPos = mul(mtxFromCols(i_data1, i_data2, i_data3, vec4(0.0, 0.0, 0.0, 1.0)), vec4(a_position, 1.0)).xyz;
#else
    vec3 worldPos = mul(u_model[0], vec4(a_position, 1.0)).xyz;
#endif
    gl_Position = mul(u_viewProj, vec4(worldPos, 1.0));
    v_color0 = a_color0;
}
#endif

#if BGFX_SHADER_TYPE_FRAGMENT
#include "./lib/common.glsl"

uniform highp vec4 StarsColor;
SAMPLER2D_HIGHP_AUTOREG(s_PreviousFrameAverageLuminance);

void main() {
    gl_FragColor = StarsColor * v_color0.a;
    gl_FragColor.rgb = preExposeLighting(gl_FragColor.rgb, texture2D(s_PreviousFrameAverageLuminance, vec2_splat(0.5)).r);
}
#endif
