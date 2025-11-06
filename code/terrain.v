#version 450
// This is the vertex data layout that we defined in initialize_render after line 198
layout(location = 0) in vec3 a_Position;

// This is what the vertex shader will output and send to the fragment shader.
layout(location = 0) out vec3 pos;

#define PI 3.141592653589793238462

void main() {
    // The fragment shader also calculates the fractional brownian motion for pixel perfect normal vectors and lighting, so we pass the vertex position to the fragment shader
    pos = a_Position;    
    // Multiply final vertex position with model/view/projection matrices to convert to clip space
    gl_Position = vec4(pos,1);
}