
#version 450

#define _Seed 17 // TODO: make this a parameter
#define PI 3.141592653589793238462

layout(location = 0) in vec3 clipPos;
layout(set = 0, binding = 0, std140) uniform UBO{
    mat4 MVP; // 0-15
};

// This is what the fragment shader will output, usually just a pixel color
layout(location = 0) out vec4 frag_color;

// UE4's PseudoRandom function
// https://github.com/EpicGames/UnrealEngine/blob/release/Engine/Shaders/Private/Random.ush
float pseudo(vec2 v) {
    v = fract(v/128.)*128. + vec2(-64.340622, -72.465622);
    return fract(dot(v.xyx * v.xyy, vec3(20.390625, 60.703125, 2.4281209)));
}

float hash(vec2 pos) {
    return pseudo(pos * vec2(_Seed, _Seed*_Seed));
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
    vec2 p1 = floor(pos);
    vec2 p2 = vec2(floor(pos.x), ceil(pos.y));
    vec2 p3 = vec2(ceil(pos.x), floor(pos.y));
    vec2 p4 = ceil(pos);
    vec2 g1 = randVec2(p1); 
    vec2 g2 = randVec2(p2); 
    vec2 g3 = randVec2(p3); 
    vec2 g4 = randVec2(p4); 
    float d1 = dot(normalize(pos - p1), g1); // 00
    float d2 = dot(normalize(pos - p2), g2); // 01
    float d3 = dot(normalize(pos - p3), g3); // 10
    float d4 = dot(normalize(pos - p4), g4); // 11
    float h1 = qerp(d1,d3, pos.x - p1.x);
    float h2 = qerp(d2,d4, pos.x - p1.x);
    float h =  qerp(h1,h2, pos.y - p1.y);
    return h;
}


void main() {
    // Convert from linear rgb to srgb for proper color output, ideally you'd do this as some final post processing effect because otherwise you will need to revert this gamma correction elsewhere
    vec2 h1 = randVec2(ceil(clipPos.xz));
    vec2 h2 = randVec2(floor(clipPos.xz));
    float h = perlin(clipPos.xz);
    // h = randVec2(vec2(12.,12.));
    frag_color = vec4(h1.x * 0,h1.y * 0,h,1.0);
}