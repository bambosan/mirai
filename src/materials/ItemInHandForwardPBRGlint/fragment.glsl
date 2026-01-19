#define MATERIAL_ITEM_IN_HAND_FORWARD_PBR_GLINT

$input v_mers
$input v_color0
$input v_absorbColor
$input v_scatterColor
$input v_worldPos
$input v_clipPos
$input v_normal
$input v_prevWorldPos
$input v_layerUV

#include "bgfx_shader.sh"
#include "item_in_hand_forward.glsl"
