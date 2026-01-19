vec4 a_color0 : COLOR0;
vec4 a_tangent : TANGENT;
vec4 a_normal : NORMAL;
vec3 a_position : POSITION;
vec2 a_texcoord0 : TEXCOORD0;
vec2 a_texcoord1 : TEXCOORD1;
int a_texcoord4 : TEXCOORD4;

vec4 i_data1 : TEXCOORD7;
vec4 i_data2 : TEXCOORD6;
vec4 i_data3 : TEXCOORD5;

vec3 v_worldPos : TEXCOORD2;
vec4 v_clipPos : TEXCOORD3;
vec3 v_tangent : TANGENT;
vec3 v_normal : NORMAL;
vec3 v_bitangent : BITANGENT;
vec4 v_color0 : COLOR0;
flat vec3 v_absorbColor : COLOR1;
flat vec3 v_scatterColor : COLOR2;
vec2 v_texcoord0 : TEXCOORD0;
vec2 v_lightmapUV : TEXCOORD1;
flat int v_pbrTextureId : TEXCOORD4;
