
#version 450

layout(location = 0) in vec3 pos;
layout(set = 0, binding = 0, std140) uniform UBO{
    mat4 MVP; // 0-15
};

// This is what the fragment shader will output, usually just a pixel color
layout(location = 0) out vec4 frag_color;

void main() {
    // Convert from linear rgb to srgb for proper color output, ideally you'd do this as some final post processing effect because otherwise you will need to revert this gamma correction elsewhere
    frag_color = vec4(0.0,0.2,0.2,1.0);
}