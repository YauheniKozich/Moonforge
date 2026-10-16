#ifndef SceneEnvironment_h
#define SceneEnvironment_h
#include <metal_stdlib>
#include "ShaderTypes.h"
#include "SceneFog.h"
using namespace metal;

// A level cylindrical panorama: each source vertical lies in a plane through the viewer.
// Projecting that plane keeps building verticals straight for every camera orientation.
inline float2 gothicPanoramaUV(float3 direction, constant MoonParameters& moon) {
    float horizontal = max(length(direction.xz), 0.0001);
    return float2(moon.panoramaMapping.x + atan2(direction.x, -direction.z) / (2.0 * M_PI_F),
                  moon.panoramaMapping.y - direction.y / horizontal * moon.panoramaMapping.z);
}

// Blend only a narrow longitude strip to reconcile residual edge differences in the artwork.
// Beyond the cylinder's captured vertical range, fade into planar cloud/ground caps.
inline float3 sampleCylindricalPanorama(texture2d<float> sky, float3 direction, float2 uv, float mip, float capMip) {
    constexpr sampler sampling(coord::normalized, s_address::repeat,
                                t_address::clamp_to_edge, filter::linear, mip_filter::linear);
    float u = fract(uv.x);
    constexpr float seamWidth = 0.025;
    float3 color;
    if (u < seamWidth || u > 1.0 - seamWidth) {
        float offset = u < seamWidth ? u : u - 1.0;
        float progress = (offset + seamWidth) * 0.5;
        float3 left = sky.sample(sampling, float2(1.0 - seamWidth + progress, uv.y), level(mip)).rgb;
        float3 right = sky.sample(sampling, float2(progress, uv.y), level(mip)).rgb;
        color = mix(left, right, smoothstep(-seamWidth, seamWidth, offset));
    } else {
        color = sky.sample(sampling, uv, level(mip)).rgb;
    }
    float capWeight = 1.0 - smoothstep(-0.10, 0.22, uv.y);
    capWeight = max(capWeight, smoothstep(0.92, 1.08, uv.y));
    if (capWeight > 0.0) {
        bool upper = uv.y < 0.5;
        // Planar coordinates have no longitude singularity at the zenith/nadir.
        float2 capUV = float2(0.5, upper ? 0.13 : 0.85)
            + direction.xz / max(abs(direction.y), 0.001) * float2(0.06, 0.18);
        capUV.y = upper ? clamp(capUV.y, 0.02, 0.24) : clamp(capUV.y, 0.75, 0.98);
        float3 cap = sky.sample(sampling, capUV, level(capMip)).rgb;
        color = mix(color, cap, capWeight);
    }
    return color;
}

// One world-space angular disk, independent of the panoramic texture and its UV seam.
inline float3 composeSceneMoon(float3 background, texture2d<float> atlas, float3 direction,
                               float blur, constant MoonParameters& moon) {
    if (atlas.get_width() == 0) return background;
    float3 lightDirection = moon.direction.xyz;
    float facing = dot(direction, lightDirection);
    if (facing <= 0.0) return background;
    float3 referenceUp = abs(lightDirection.y) > 0.99 ? float3(1,0,0) : float3(0,1,0);
    float3 right = normalize(cross(lightDirection, referenceUp));
    float3 up = cross(right, lightDirection);
    float radius = clamp(moon.direction.w, 0.001, 0.3);
    float expandedRadius = radius + blur * blur * 0.3;
    float2 disk = float2(dot(direction, right), dot(direction, up)) / (facing * tan(expandedRadius));
    float radial = length(disk);
    float feather = 0.02 + blur * 0.8;
    float coverage = 1.0 - smoothstep(1.0 - feather, 1.0 + feather, radial);
    if (coverage <= 0.0) return background;
    constexpr sampler moonSampler(coord::normalized, address::clamp_to_edge,
                                   filter::linear, mip_filter::linear);
    float2 uv = moon.textureRegion.xy + clamp(disk, -1.0, 1.0) * float2(1,-1) * moon.textureRegion.zw;
    float3 color = atlas.sample(moonSampler, uv, level(blur * 3.0)).rgb * moon.panoramaMapping.w;
    // Mip-based IBL broadens the disk approximately while retaining its total contribution.
    float energy = pow(tan(radius) / tan(expandedRadius), 2.0);
    return mix(background, color, coverage * energy);
}

// Ordinary image mips approximate rough reflections; these are not GGX-prefiltered probes.
inline float3 sampleSceneEnvironment(texture2d<float> sky, texture2d<float> moonAtlas,
                                     float3 direction, float mip, float3 world,
                                     constant FogParameters& fog, constant MoonParameters& moon) {
    if (sky.get_width() == 0) return float3(0.12, 0.16, 0.22);
    float3 color = sampleCylindricalPanorama(sky, direction, gothicPanoramaUV(direction, moon), mip, mip);
    float maxMip = max(float(sky.get_num_mip_levels()) - 1.0, 1.0);
    color = composeSceneMoon(color, moonAtlas, direction, saturate(mip / maxMip), moon);
    return fogSkyColor(color, world, direction, fog);
}
#endif
