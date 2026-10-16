#ifndef SceneMaterials_h
#define SceneMaterials_h
#include <metal_stdlib>
#include "SceneEnvironment.h"
#include "SceneLighting.h"
using namespace metal;

struct SurfaceMaterial {
    float3 baseColor;
    float roughness; // Authored perceptual roughness; squared once for the GGX alpha.
    float metallic;
    float dielectricF0;
};

inline float3 surfaceF0(SurfaceMaterial material) {
    return mix(float3(material.dielectricF0), material.baseColor, material.metallic);
}

inline float3 surfaceFresnel(float3 f0, float cosine) {
    float grazing = pow(1.0 - saturate(cosine), 5.0);
    return f0 + (1.0 - f0) * grazing;
}

// Cook-Torrance GGX, correlated Smith visibility and Schlick Fresnel.
// Formula reference: https://google.github.io/filament/main/filament.html
inline float3 directSurfaceLight(SurfaceMaterial material, float3 n, float3 v,
                                 float3 l, float3 radiance) {
    float noL = saturate(dot(n, l));
    float noV = saturate(dot(n, v));
    if (noL <= 0.0 || noV <= 0.0) return float3(0);
    float3 halfVector = l + v;
    float halfLengthSquared = dot(halfVector, halfVector);
    if (halfLengthSquared < 0.000001) return float3(0);
    float3 h = halfVector * rsqrt(halfLengthSquared);
    float noH = saturate(dot(n, h));
    float voH = saturate(dot(v, h));
    float roughness = clamp(material.roughness, 0.06, 1.0);
    float alpha = roughness * roughness;
    float alphaSquared = alpha * alpha;
    // Cross-product form avoids cancellation at the peak of smooth highlights.
    float3 nxh = cross(n, h);
    float denominator = dot(nxh, nxh) + noH * noH * alphaSquared;
    float distribution = alphaSquared / max(M_PI_F * denominator * denominator, 1e-12);
    float ggxV = noL * sqrt(noV * noV * (1.0 - alphaSquared) + alphaSquared);
    float ggxL = noV * sqrt(noL * noL * (1.0 - alphaSquared) + alphaSquared);
    float visibility = 0.5 / max(ggxV + ggxL, 1e-6);
    float3 fresnel = surfaceFresnel(surfaceF0(material), voH);
    float3 diffuse = (1.0 - fresnel) * (1.0 - material.metallic) * material.baseColor / M_PI_F;
    float3 specular = fresnel * distribution * visibility;
    return (diffuse + specular) * radiance * noL;
}

inline float3 shadeSurface(SurfaceMaterial material, float3 world, float3 n, float3 v,
                           float moonVisibility, float sceneTime, texture2d<float> sky, texture2d<float> moonAtlas,
                           constant FogParameters& fog, constant MoonParameters& moon) {
    float3 f0 = surfaceF0(material);
    float noV = saturate(dot(n, v));
    float roughness = clamp(material.roughness, 0.06, 1.0);
    // Roughness-aware grazing response approximates BRDF integration for the mip-based environment.
    float3 grazingReflectance = max(float3(1.0 - roughness), f0);
    float3 viewFresnel = f0 + (grazingReflectance - f0) * pow(1.0 - noV, 5.0);
    float maxMip = sky.get_width() > 0 ? float(sky.get_num_mip_levels() - 1) : 0.0;
    float3 reflected = reflect(-v, n);
    float3 reflectedLight = sampleSceneEnvironment(sky, moonAtlas, reflected, roughness * maxMip, world, fog, moon);
    float3 diffuseEnvironment = sampleSceneEnvironment(sky, moonAtlas, n, maxMip * 0.85, world, fog, moon);
    // An artistic hemisphere fill supplies indirect light absent from the single LDR panorama.
    float3 indirect = mix(float3(0.12, 0.14, 0.18), float3(0.24, 0.28, 0.36), n.y * 0.5 + 0.5);
    float3 diffuseWeight = (1.0 - viewFresnel) * (1.0 - material.metallic);
    float3 color = diffuseWeight * material.baseColor * (indirect + diffuseEnvironment);
    color += reflectedLight * viewFresnel;
    color += directSurfaceLight(material, n, v, moon.direction.xyz,
                                float3(0.72, 0.83, 1.0) * 3.5) * moonVisibility;
    // Soft unshadowed fill preserves readability on the side opposite the moon.
    color += directSurfaceLight(material, n, v, normalize(float3(-0.6, 0.35, 0.5)),
                                float3(0.48, 0.54, 0.66));
    const float lampX[4] = {-2.2, -0.8, 0.8, 2.2};
    for (int lamp = 0; lamp < 4; ++lamp) {
        float3 delta = float3(lampX[lamp], -0.25, -2.03) - world;
        float distance = max(length(delta), 0.001);
        float3 radiance = float3(0.34, 0.09, 0.015) * M_PI_F
            * exp(-distance * 4.0) * lanternFlicker(sceneTime, lampX[lamp]);
        color += directSurfaceLight(material, n, v, delta / distance, radiance);
    }
    return max(color, float3(0));
}
#endif
