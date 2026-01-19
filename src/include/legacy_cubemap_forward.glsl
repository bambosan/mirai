#if BGFX_SHADER_TYPE_VERTEX
void main() {
    gl_Position = vec4_splat(-1.0);
}
#endif

#if BGFX_SHADER_TYPE_FRAGMENT
void main() {
    gl_FragColor = vec4_splat(0.0);
}
#endif
