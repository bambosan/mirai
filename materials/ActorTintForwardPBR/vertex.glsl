#define MATERIAL_ACTOR_TINT_FORWARD_PBR

$input a_color0
$input a_tangent
$input a_normal
$input a_indices
$input a_position
$input a_texcoord0

#if INSTANCING__ON
$input i_data1
$input i_data2
$input i_data3
#endif

$output v_worldPos
$output v_clipPos
$output v_tangent
$output v_bitangent
$output v_normal
$output v_color0
$output v_absorbColor
$output v_scatterColor
$output v_texcoord0

#include "bgfx_shader.sh"
#include "actor_forward.glsl"
