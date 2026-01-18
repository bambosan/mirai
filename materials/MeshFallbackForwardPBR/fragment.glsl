#define MATERIAL_MESH_FALLBACK_FORWARD_PBR

$input v_color0
$input v_absorbColor
$input v_scatterColor
$input v_worldPos
$input v_clipPos
$input v_texcoord0

#include "bgfx_shader.sh"
#include "mesh_fallback_forward.glsl"
