#include <metal_stdlib>
using namespace metal;
struct ShadowPosition { float3 position [[attribute(0)]]; };
vertex float4 vertex_shadow_stone(ShadowPosition in [[stage_in]], constant float4x4& transform [[buffer(2)]]) {
    return transform * float4(in.position,1);
}

struct ShadowModel { float3 position [[attribute(0)]]; float2 uv [[attribute(3)]]; };
struct ShadowOutput { float4 position [[position]]; float2 uv; };
vertex ShadowOutput vertex_shadow_model(ShadowModel in [[stage_in]], constant float4x4& transform [[buffer(2)]]) {
    ShadowOutput out;
    out.position = transform * float4(in.position,1);
    out.uv = in.uv;
    return out;
}

fragment void fragment_shadow_model(ShadowOutput in [[stage_in]], texture2d<float> color [[texture(0)]], sampler sampling [[sampler(0)]], constant uint& textured [[buffer(3)]], constant float& baseAlpha [[buffer(4)]]) {
    float alpha = baseAlpha;
    if (textured != 0 && color.get_width() > 0) {
        alpha *= color.sample(sampling,in.uv).a;
    }
    if (alpha < 0.01) discard_fragment();
}
