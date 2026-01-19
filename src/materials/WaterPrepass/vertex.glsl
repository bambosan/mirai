$input a_color0
$input a_normal
$input a_tangent
$input a_position
$input a_texcoord1

#if INSTANCING__ON
$input i_data1
$input i_data2
$input i_data3
#endif

$output v_worldPos
$output v_tangent
$output v_bitangent
$output v_normal
$output v_lightmapUV

#include "bgfx_shader.sh"
#include "water_prepass.glsl"
