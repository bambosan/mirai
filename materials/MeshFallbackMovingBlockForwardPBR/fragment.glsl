#define MATERIAL_MESH_FALLBACK_MOVING_BLOCK_FORWARD_PBR

$input v_worldPos
$input v_clipPos
$input v_tangent
$input v_bitangent
$input v_normal
$input v_color0
$input v_absorbColor
$input v_scatterColor
$input v_texcoord0
$input v_pbrTextureId

#include "bgfx_compute.sh"
#include "mesh_fallback_forward.glsl"
