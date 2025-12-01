#version 450

// This is the vertex data layout that we defined in initialize_render after line 198
layout(location = 0) in vec3 a_Position;

layout(set = 0, binding = 0, std140) uniform UBO{
    mat4 MVP; // 0-15
    float displacementAmount; // 16
    float noise; // 17
    vec2 offset; // 18-19
    vec2 scale;  // 20-21
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
    return pseudo(pos * vec2(noise, noise +4));
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

float quinticInterpolator(float t){
    float t3 = pow(t,3);
    return 6 * pow(t,2) * t3 - 15 * t3 * t + 10 * t3;
}

// Fifth order interpolant function from https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-5-implementing-improved-perlin-noise
float qerp(float from, float to, float t){
    float q = quinticInterpolator(t);
    return from * (1-q) + to * q;
}

float perlin(vec2 pos){
    vec2 f = floor(pos);
    vec2 c = ceil(pos);
    vec2 r = fract(pos);
    vec2 rc = r-vec2(1.0); // Used to optimize computation of d. x - floor(x) = fract(x) and x-ceil(x) = fract(x) - 1.0

    vec2 p1 = f; // 00
    vec2 p2 = vec2(c.x, f.y); // 10
    vec2 p3 = vec2(f.x, c.y); // 01
    vec2 p4 = c;            // 11
    // Gradients
    vec2 g1 = randVec2(p1); 
    vec2 g2 = randVec2(p2); 
    vec2 g3 = randVec2(p3); 
    vec2 g4 = randVec2(p4); 
    // Noise values (TODO: optimize the difference)
    float d1 = dot(r, g1)  ; // 00
    float d2 = dot(vec2(rc.x, r.y) , g2); // 10
    float d3 = dot(vec2(r.x, rc.y) , g3) ; // 01
    float d4 = dot(rc, g4) ; // 11
    
    // idk if should use this one
    // vec2 u = vec2(quinticInterpolator(r.x), quinticInterpolator(r.y));
    // float noiseH = d1 + u.x * (d2 - d1) + u.y * (d3 - d1) + u.x * u.y * (d1 - d2 - d3 + d4);
    float h1 = qerp(d1,d2, r.x);
    float h2 = qerp(d3,d4, r.x);
    float h =  qerp(h1,h2, r.y);
    return h;
}

float fbm(vec2 pos){
    float h = 0;
    for (int i =1; i <= 32; i++){
        h += perlin(pos * 1.1 * i) / (1.1*i);
    }
    return h;
}

void main() {
    // The fragment shader also calculates the fractional brownian motion for pixel perfect normal vectors and lighting, so we pass the vertex position to the fragment shader
    clipPos = a_Position;
    float h = fbm((clipPos.xz + offset) /scale);
    clipPos.y +=  (displacementAmount / 2.0) + (h  * displacementAmount);   
    // Multiply final vertex position with model/view/projection matrices to convert to clip space
    gl_Position = MVP*vec4(clipPos,1);
    vCol = vec3(h,h,h);
}