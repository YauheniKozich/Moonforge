#include <metal_stdlib>
using namespace metal;

kernel void bloom_extract(texture2d<float,access::read> scene [[texture(0)]], texture2d<float,access::write> bright [[texture(1)]], uint2 pixel [[thread_position_in_grid]]) {
    if (pixel.x >= bright.get_width() || pixel.y >= bright.get_height()) return;
    float3 color = 0;
    // Threshold before downsampling so small glowing eyes do not disappear.
    for (uint y=0;y<4;++y) for (uint x=0;x<4;++x) {
        uint2 p = min(pixel*4+uint2(x,y),uint2(scene.get_width()-1,scene.get_height()-1));
        float3 sample = scene.read(p).rgb;
        float peak = max(sample.r,max(sample.g,sample.b));
        float contribution = smoothstep(0.65,0.9,peak);
        color += sample * contribution;
    }
    bright.write(float4(color/16.0,1),pixel);
}

kernel void bloom_blur(texture2d<float,access::read> source [[texture(0)]], texture2d<float,access::write> destination [[texture(1)]], constant int2& direction [[buffer(0)]], uint2 pixel [[thread_position_in_grid]]) {
    if (pixel.x >= destination.get_width() || pixel.y >= destination.get_height()) return;
    const float weights[5] = {0.227027,0.1945946,0.1216216,0.054054,0.016216};
    float3 color = source.read(pixel).rgb * weights[0];
    int2 limit = int2(source.get_width()-1,source.get_height()-1);
    for (int i=1;i<5;++i) {
        color += source.read(uint2(clamp(int2(pixel)+direction*i,int2(0),limit))).rgb * weights[i];
        color += source.read(uint2(clamp(int2(pixel)-direction*i,int2(0),limit))).rgb * weights[i];
    }
    destination.write(float4(color,1),pixel);
}

struct BloomOutput { float4 position [[position]]; float2 uv; };
vertex BloomOutput vertex_bloom_composite(uint id [[vertex_id]]) {
    float2 vertices[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)};
    BloomOutput out;
    out.position = float4(vertices[id],0,1);
    out.uv = vertices[id] * float2(0.5,-0.5) + 0.5;
    return out;
}

fragment float4 fragment_bloom_composite(BloomOutput in [[stage_in]], texture2d<float> scene [[texture(0)]], texture2d<float> bloom [[texture(1)]]) {
    constexpr sampler sampling(coord::normalized, address::clamp_to_edge, filter::linear);
    float3 color = scene.sample(sampling,in.uv).rgb;
    float3 glow = bloom.sample(sampling,in.uv).rgb;
    float3 hdr = max(color + glow * 0.65, float3(0));
    // Fitted ACES tone mapping preserves bright-source detail for the SDR drawable.
    float3 mapped = (hdr * (2.51 * hdr + 0.03)) / (hdr * (2.43 * hdr + 0.59) + 0.14);
    return float4(clamp(mapped, 0.0, 1.0),1);
}
