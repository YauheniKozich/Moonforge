#include <metal_stdlib>
#include "ShaderTypes.h"
#include "SceneFog.h"
#include "SceneLighting.h"
#include "SceneMaterials.h"
using namespace metal;

struct SkyOutput { float4 position [[position]]; float3 direction; };
vertex SkyOutput vertex_gothic_sky(uint id [[vertex_id]], constant float4x4& inverse [[buffer(2)]]) {
    float2 points[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
    float2 p = points[id];
    float4 nearPoint = inverse * float4(p, 0, 1);
    float4 farPoint = inverse * float4(p, 1, 1);
    SkyOutput out;
    out.position = float4(p, 1, 1);
    out.direction = farPoint.xyz / farPoint.w - nearPoint.xyz / nearPoint.w;
    return out;
}

fragment float4 fragment_gothic_sky(SkyOutput in [[stage_in]], texture2d<float> panorama [[texture(0)]], texture2d<float> moonAtlas [[texture(7)]], sampler sampling [[sampler(0)]], constant FogParameters& fog [[buffer(6)]], constant MoonParameters& moon [[buffer(7)]]) {
    float3 direction = normalize(in.direction);
    float2 uv = gothicPanoramaUV(direction, moon);
    // Unwrap longitude derivatives so the atan2 branch cut does not select a coarse mip.
    float2 uvDX = dfdx(uv);
    float2 uvDY = dfdy(uv);
    uvDX.x -= round(uvDX.x);
    uvDY.x -= round(uvDY.x);
    float2 size = float2(panorama.get_width(), panorama.get_height());
    float footprint = max(length(uvDX * size), length(uvDY * size));
    float mip = log2(max(footprint, 1.0));
    float3 color = sampleCylindricalPanorama(panorama, direction, uv, mip, 2.0);
    color = composeSceneMoon(color, moonAtlas, direction, 0.0, moon);
    return float4(fogSkyColor(color, fog.cameraPosition.xyz, direction, fog), 1);
}

struct StoneInput { float3 position [[attribute(0)]]; float3 normal [[attribute(1)]]; float3 tint [[attribute(2)]]; };
struct StoneOutput { float4 position [[position]]; float3 world; float3 normal; float3 tint; float3 viewDirection; };
vertex StoneOutput vertex_stone(StoneInput in [[stage_in]], constant Uniforms& uniforms [[buffer(2)]]) {
    StoneOutput out;
    float4 view = uniforms.viewMatrix * float4(in.position, 1);
    out.position = uniforms.projectionMatrix * view;
    out.world = in.position;
    out.normal = in.normal;
    out.tint = in.tint;
    float3x3 rotation(uniforms.viewMatrix[0].xyz,uniforms.viewMatrix[1].xyz,uniforms.viewMatrix[2].xyz);
    float3 eye = -(transpose(rotation) * uniforms.viewMatrix[3].xyz);
    out.viewDirection = eye - in.position;
    return out;
}

fragment float4 fragment_stone(StoneOutput in [[stage_in]], texture2d<float> stone [[texture(0)]], sampler sampling [[sampler(0)]],
    texture2d<float> sky [[texture(6)]],
    texture2d<float> moonAtlas [[texture(7)]],
    depth2d<float> moonDepth [[texture(5)]], sampler moonComparison [[sampler(1)]], constant float4x4& moonMatrix [[buffer(4)]], constant float& sceneTime [[buffer(5)]], constant FogParameters& fog [[buffer(6)]], constant MoonParameters& moon [[buffer(7)]]) {
    float3 n = normalize(in.normal);
    float3 view = normalize(in.viewDirection);
    float2 uv = abs(n.y) > 0.5 ? in.world.xz : float2(in.world.x + in.world.z, in.world.y);
    float3 albedo = stone.sample(sampling, uv * 0.65).rgb * in.tint * 3.0;
    if (in.tint.r < 0) albedo = float3(-in.tint.r, in.tint.g, in.tint.b);
    bool pedestal = in.world.y > -1.115 && in.world.y < -0.97
        && length(in.world.xz) < 1.2 && n.y > 0.5 && in.tint.b > 0.3;
    if (pedestal) albedo *= 0.62;
    SurfaceMaterial stoneMaterial = {clamp(albedo, 0.0, 1.0), 0.86, 0.0, 0.04};
    float visibility = moonShadow(in.world, moonMatrix, moonDepth, moonComparison);
    float3 color = shadeSurface(stoneMaterial, in.world, n, view, visibility, sceneTime, sky, moonAtlas, fog, moon);
    if (pedestal) {
        // A non-metallic water coat adds sharper reflections over the rough stone substrate.
        SurfaceMaterial waterCoat = {float3(0), 0.16, 0.0, 0.02};
        float3 coatFresnel = surfaceFresnel(float3(0.02), max(dot(n, view), 0.0));
        color *= 1.0 - coatFresnel;
        color += shadeSurface(waterCoat, in.world, n, view, visibility, sceneTime, sky, moonAtlas, fog, moon);
    }
    if (in.tint.r > 1) color = in.tint * lanternFlicker(sceneTime, in.world.x);
    color = applySceneFog(color, in.world, fog);
    return float4(color,1);
}
