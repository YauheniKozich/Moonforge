#ifndef SceneFog_h
#define SceneFog_h
#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

// Average of exp(-x*t), t in [0,1]. Series avoids cancellation for horizontal rays.
inline float fogExponentialMean(float x) {
    if (x < 0.001) return 1.0 - x * 0.5 + x * x / 6.0;
    return (1.0 - exp(-x)) / x;
}

inline float fogTransmittance(float3 origin, float3 destination, constant FogParameters& fog) {
    float distance = length(destination - origin);
    float density = max(fog.colorDensity.w, 0.0);
    float falloff = max(fog.height.y, 0.0);
    float low = min(origin.y, destination.y) - fog.height.x;
    float high = max(origin.y, destination.y) - fog.height.x;
    float meanDensity;
    if (high <= 0.0) {
        meanDensity = 1.0;
    } else if (low >= 0.0) {
        meanDensity = exp(-falloff * low) * fogExponentialMean(falloff * (high - low));
    } else {
        // Split at the base plane: density below it is capped, rather than growing unbounded.
        float aboveFraction = high / (high - low);
        meanDensity = (1.0 - aboveFraction) + aboveFraction * fogExponentialMean(falloff * high);
    }
    return exp(-min(density * distance * meanDensity, 80.0));
}

inline float3 applySceneFog(float3 color, float3 world, constant FogParameters& fog) {
    float transmission = fogTransmittance(fog.cameraPosition.xyz, world, fog);
    return mix(fog.colorDensity.rgb, color, transmission);
}

inline float3 fogSkyColor(float3 color, float3 origin, float3 direction, constant FogParameters& fog) {
    float transmission = fogTransmittance(origin, origin + direction * max(fog.height.z, 0.0), fog);
    return mix(fog.colorDensity.rgb, color, transmission);
}
#endif
