$input a_color0
$input a_position
$input a_texcoord0
$input a_texcoord1

#if INSTANCING__ON
$input i_data1
$input i_data2
$input i_data3
#endif

$output v_color0
$output v_absorbColor
$output v_scatterColor
$output v_worldPos
$output v_clipPos
$output v_texcoord0
$output v_ambientLight

#include "bgfx_shader.sh"
#include "particle_forward.glsl"
