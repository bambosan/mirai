$input v_worldPos
$input v_tangent
$input v_bitangent
$input v_normal
$input v_color0
$input v_texcoord0
$input v_lightmapUV
$input v_pbrTextureId

#include "bgfx_compute.sh"
#define MATERIAL_RENDERCHUNK_PREPASS
#include "renderchunk_prepass.glsl"
