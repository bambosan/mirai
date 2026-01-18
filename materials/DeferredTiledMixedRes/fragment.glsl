#include "bgfx_shader.sh"
void main() {
#if CAUSTICS_MULTIPLIER_PASS
    gl_FragData[0] = vec4_splat(0.0);
#endif

#if DIRECTIONAL_LIGHTING_PASS
    gl_FragData[0] = vec4_splat(0.0);
    gl_FragData[1] = vec4_splat(0.0);
#endif

#if DIRECTIONAL_LIGHTING_PASS0_PASS
    gl_FragData[0] = vec4_splat(0.0);
    gl_FragData[1] = vec4_splat(0.0);
#endif

#if DIRECTIONAL_LIGHTING_PASS1_PASS
    gl_FragData[0] = vec4_splat(0.0);
    gl_FragData[1] = vec4_splat(0.0);
#endif

#if DISCRETE_INDIRECT_COMBINED_LIGHTING_PASS
    gl_FragData[0] = vec4_splat(0.0);
    gl_FragData[1] = vec4_splat(0.0);
    gl_FragData[2] = vec4_splat(0.0);
#endif

#if TILE_CLASSIFICATION_PASS || FALLBACK_PASS || SURFACE_RADIANCE_UPSCALE_PASS
    gl_FragColor = vec4_splat(0.0);
#endif
}

