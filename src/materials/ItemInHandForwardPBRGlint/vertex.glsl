#define MATERIAL_ITEM_IN_HAND_FORWARD_PBR_GLINT

$input a_color0
$input a_texcoord8
$input a_normal
$input a_position
$input a_texcoord0

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
$output v_layerUV

#include "bgfx_shader.sh"
#include "item_in_hand_forward.glsl"
