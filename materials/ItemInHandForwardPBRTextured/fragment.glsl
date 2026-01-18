#define MATERIAL_ITEM_IN_HAND_FORWARD_PBR_TEXTURED

$input v_color0
$input v_absorbColor
$input v_scatterColor
$input v_worldPos
$input v_clipPos
$input v_tangent
$input v_bitangent
$input v_normal
$input v_prevWorldPos
$input v_texcoord0
$input v_pbrTextureId

#include "bgfx_compute.sh"
#include "item_in_hand_forward.glsl"
