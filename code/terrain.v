#version 450

// This is the vertex data layout that we defined in initialize_render after line 198
layout(location = 0) in vec3 a_Position;

layout(set = 0, binding = 0, std140) uniform UBO{
    mat4 MVP; // 0-15
    float displacementAmount; // 16
    float noise; // 17
};

// This is what the vertex shader will output and send to the fragment shader.
layout(location = 0) out vec3 clipPos;
layout(location = 1) out vec3 vCol;

#define PI 3.141592653589793238462

// UE4's PseudoRandom function
// https://github.com/EpicGames/UnrealEngine/blob/release/Engine/Shaders/Private/Random.ush
float pseudo(vec2 v) {
    v = fract(v/128.)*128. + vec2(-64.340622, -72.465622);
    return fract(dot(v.xyx * v.xyy, vec3(20.390625, 60.703125, 2.4281209)));
}

float hash(vec2 pos) {
    return pseudo(pos * vec2(noise, noise * noise));
    // return pseudo(pos.xy);
}

// Generate a vector starting from an angle where 0 = 0, 1 = 360
vec2 angle01ToVec2(float angle){
    // Mapping [0,1] to a period of 4PI allows for a better distribution of values
    float theta = ((angle * 2 * 360)-360) * PI * 0.5; // [0,1] -> [0, 720] -> [-360,360] -> [-2PI, 2PI]
    return normalize(vec2(cos(theta), sin(theta)));
}

vec2 randVec2(vec2 seed){
    return angle01ToVec2(hash(seed));// <--- problem is here since it's using pos rename global position variable
}

// Fifth order interpolant function from https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-5-implementing-improved-perlin-noise
float qerp(float from, float to, float t){
    float q = 6 * pow(t,5) - 15 * pow(t,4) + 10 * pow(t,3);
    return from * (1-q) + to * q;
}

float perlin(vec2 pos){
    pos += 0.0771;
    vec2 p1 = floor(pos);
    vec2 p2 = vec2(floor(pos.x), ceil(pos.y ));
    vec2 p3 = vec2(ceil(pos.x), floor(pos.y));
    vec2 p4 = ceil(pos);
    // Gradients
    vec2 g1 = randVec2(p1) ; 
    vec2 g2 = randVec2(p2) ; 
    vec2 g3 = randVec2(p3) ; 
    vec2 g4 = randVec2(p4) ; 
    // Noise values (TODO: optimize the difference)
    float d1 = dot(pos - p1, g1); // 00
    float d2 = dot(pos - p2, g2); // 01
    float d3 = dot(pos - p3, g3); // 10
    float d4 = dot(pos - p4, g4); // 11
    

    vec2 r = fract(pos);
    float h1 = qerp(d1,d3, r.x);
    float h2 = qerp(d2,d4, r.x);
    float h =  qerp(h1,h2, r.y);
    return h;
}


void main() {
    // The fragment shader also calculates the fractional brownian motion for pixel perfect normal vectors and lighting, so we pass the vertex position to the fragment shader
    clipPos = a_Position;
    float h = perlin(clipPos.xz);
    clipPos.y += perlin(clipPos.xz) * displacementAmount;   
    // Multiply final vertex position with model/view/projection matrices to convert to clip space
    gl_Position = MVP*vec4(clipPos,1);
    vCol = vec3(h,h,h);
}