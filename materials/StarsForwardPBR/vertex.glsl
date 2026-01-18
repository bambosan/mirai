$input a_color0
$input a_position

#if INSTANCING__ON
$input i_data1
$input i_data2
$input i_data3
#endif

$output v_color0

#include "bgfx_shader.sh"
#include "stars_forward.glsl"
