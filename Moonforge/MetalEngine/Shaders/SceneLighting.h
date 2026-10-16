#ifndef SceneLighting_h
#define SceneLighting_h
#include <metal_stdlib>
using namespace metal;

inline float lanternFlicker(float time, float position) {
    return 0.94 + sin(time * 3.1 + position) * 0.04 + sin(time * 7.7 + position * 2) * 0.02;
}

inline float3 lanternLight(float3 world, float3 normal, float time) {
    float3 light = 0;
    float xs[4] = {-2.2,-0.8,0.8,2.2};
    for (int lamp=0;lamp<4;++lamp) {
        float3 delta = float3(xs[lamp],-0.25,-2.03) - world;
        float distance = max(length(delta),0.001);
        light += float3(0.34,0.09,0.015) * exp(-distance*4.0)
            * max(dot(normal,delta/distance),0.0) * lanternFlicker(time,xs[lamp]);
    }
    return light;
}

inline float moonShadow(float3 world, constant float4x4& lightMatrix, depth2d<float> map, sampler comparison) {
    if (map.get_width() == 0) return 1.0;
    float4 projected = lightMatrix * float4(world,1);
    float3 ndc = projected.xyz / projected.w;
    float2 uv = ndc.xy * float2(0.5,-0.5) + 0.5;
    if (any(uv < 0) || any(uv > 1) || ndc.z < 0 || ndc.z > 1) return 1.0;
    float visibility = 0;
    float texel = 1.0 / float(map.get_width());
    for (int y=-1;y<=1;++y) for (int x=-1;x<=1;++x) {
        visibility += map.sample_compare(comparison, uv + float2(x,y)*texel, ndc.z-0.001);
    }
    return visibility / 9.0;
}
#endif
