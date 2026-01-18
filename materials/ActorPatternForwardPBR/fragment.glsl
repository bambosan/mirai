#define MATERIAL_ACTOR_PATTERN_FORWARD_PBR

$input v_worldPos
$input v_clipPos
$input v_tangent
$input v_bitangent
$input v_normal
$input v_color0
$input v_absorbColor
$input v_scatterColor
$input v_texcoord0

#include "bgfx_shader.sh"
#include "actor_forward.glsl"
