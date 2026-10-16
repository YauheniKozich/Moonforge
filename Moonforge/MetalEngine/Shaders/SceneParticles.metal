#include <metal_stdlib>
#include "ShaderTypes.h"
#include "SceneFog.h"
using namespace metal;

struct FireflyOutput {
    float4 position [[position]];
    float2 uv;
    float brightness;
    float3 worldPosition;
};

float particleSeed(uint id, uint salt) {
    uint bits = (id + salt) * 747796405u + 2891336453u;
    bits = ((bits >> ((bits >> 28u) + 4u)) ^ bits) * 277803737u;
    bits = (bits >> 22u) ^ bits;
    return float(bits & 0x00ffffffu) / 16777215.0;
}

vertex FireflyOutput vertex_firefly(uint vertexID [[vertex_id]], uint id [[instance_id]],
    constant Uniforms& camera [[buffer(2)]], constant float& time [[buffer(5)]]) {
    const float2 corners[6] = {float2(-1,-1),float2(1,-1),float2(1,1),float2(-1,-1),float2(1,1),float2(-1,1)};
    float phase = particleSeed(id,11) * 2 * M_PI_F;
    // Integer frequencies keep motion continuous when the renderer's 1024s clock wraps.
    float t = time * (2 * M_PI_F / 1024.0);
    float3 center = float3(mix(-2.8,2.8,particleSeed(id,31)),
                          mix(-0.8,1.45,particleSeed(id,57)),
                          mix(-4.2,0.65,particleSeed(id,93)));
    center += float3(sin(t*36+phase)*0.18,sin(t*54+phase)*0.15,cos(t*29+phase)*0.12);
    float radius = mix(0.006,0.013,particleSeed(id,125));
    float4 view = camera.viewMatrix * float4(center,1);
    // Camera-facing quads have a world-space size, so distant lights appear smaller.
    view.xy += corners[vertexID] * radius;
    FireflyOutput out;
    out.position = camera.projectionMatrix * view;
    out.uv = corners[vertexID];
    float3x3 viewRotation(camera.viewMatrix[0].xyz, camera.viewMatrix[1].xyz, camera.viewMatrix[2].xyz);
    out.worldPosition = center + transpose(viewRotation) * float3(corners[vertexID] * radius, 0);
    out.brightness = 0.45 + 0.55 * pow(sin(t*251+phase)*0.5+0.5,2.0);
    return out;
}

fragment float4 fragment_firefly(FireflyOutput in [[stage_in]], constant FogParameters& fog [[buffer(6)]]) {
    float radius = dot(in.uv,in.uv);
    if (radius > 1) discard_fragment();
    float soft = exp(-radius*5.5) * (1-smoothstep(0.65,1.0,radius));
    float transmission = fogTransmittance(fog.cameraPosition.xyz, in.worldPosition, fog);
    // Additive particles contribute emission only; adding fog color here would create halos.
    return float4(float3(2.4,1.65,0.42) * transmission,soft*in.brightness);
}
