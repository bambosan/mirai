$input a_color0
$input a_texcoord8
$input a_normal
$input a_position

#if INSTANCING__ON
$input i_data1
$input i_data2
$input i_data3
#endif

$output v_mers
$output v_color0
$output v_absorbColor
$output v_scatterColor
$output v_worldPos
$output v_clipPos
$output v_normal
$output v_prevWorldPos

#include "bgfx_shader.sh"
#include "item_in_hand_forward.glsl"
