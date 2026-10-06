#if SHADER_STAGE__VERTEX
void main() {
    gl_Position = vec4(0.0);
}
#endif

#if SHADER_STAGE__FRAGMENT
out vec4 fragColor;
void main() {
    fragColor = vec4(0.0);
}
#endif
