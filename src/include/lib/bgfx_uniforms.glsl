#ifndef BGFX_UNIFORMS_DEFINED
#define BGFX_UNIFORMS_DEFINED

uniform vec4  u_viewRect;
uniform vec4  u_viewTexel;
uniform mat4  u_view;
uniform mat4  u_invView;
uniform mat4  u_proj;
uniform mat4  u_invProj;
uniform mat4  u_viewProj;
uniform mat4  u_invViewProj;
uniform mat4  u_model[BGFX_CONFIG_MAX_BONES];
uniform mat4  u_modelView;
uniform mat4  u_modelViewProj;
uniform vec4  u_alphaRef4;
uniform vec4  u_prevWorldPosOffset;
uniform mat4  u_prevViewProj;

#endif
