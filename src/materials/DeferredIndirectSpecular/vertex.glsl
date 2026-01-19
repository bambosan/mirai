$input a_position
$input a_texcoord0

$output v_absorbColor
$output v_scatterColor
$output v_texcoord0
$output v_projPos

#include "bgfx_shader.sh"
#include "deferred_indirect_specular.glsl"
