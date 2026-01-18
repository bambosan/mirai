#if BGFX_SHADER_LANGUAGE_GLSL
float a_indices : BLENDINDICES;
#else
int a_indices : BLENDINDICES;
#endif
vec4 a_color0 : COLOR0;
vec4 a_tangent : TANGENT;
vec4 a_normal : NORMAL;
vec3 a_position : POSITION;
vec2 a_texcoord0 : TEXCOORD0;

vec4 i_data1 : TEXCOORD7;
vec4 i_data2 : TEXCOORD6;
vec4 i_data3 : TEXCOORD5;

vec3 v_worldPos : TEXCOORD2;
vec4 v_clipPos : TEXCOORD3;
vec3 v_tangent : TANGENT;
vec3 v_bitangent : BITANGENT;
vec3 v_normal : NORMAL;
vec4 v_color0 : COLOR0;
flat vec3 v_absorbColor : COLOR1;
flat vec3 v_scatterColor : COLOR2;
centroid vec2 v_texcoord0 : TEXCOORD0;
centroid vec4 v_texcoords : TEXCOORD1;
