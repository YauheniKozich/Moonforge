#include <metal_stdlib>
#include "ShaderTypes.h"
#include "SceneFog.h"
#include "SceneLighting.h"
#include "SceneMaterials.h"

using namespace metal;

// MARK: - Vertex Output

struct VertexOut {
    float4 position [[position]];
    float3 color;
    float3 worldPosition;
};

struct ModelVertexIn {
    float3 position [[attribute(AttributeIndexPosition)]];
    float3 normal [[attribute(AttributeIndexNormal)]];
    float2 uv [[attribute(AttributeIndexUV)]];
};

struct ModelVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 uv;
    float3 viewDirection;
};

// MARK: - Vertex Shader

vertex VertexOut vertex_main(
    const device Vertex* vertices [[buffer(BufferIndexVertices)]],
    constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]],
    uint id [[vertex_id]]
) {
    VertexOut out;
    float4 position = float4(vertices[id].position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * position;
    out.color = vertices[id].color;
    out.worldPosition = (uniforms.modelMatrix * position).xyz;
    return out;
}

// MARK: - Fragment Shader

fragment float4 fragment_main(
    VertexOut in [[stage_in]],
    constant FogParameters& fog [[buffer(6)]]
) {
    return float4(applySceneFog(in.color, in.worldPosition, fog), 1.0);
}

// MARK: - Model Shaders

vertex ModelVertexOut vertex_model(
    ModelVertexIn in [[stage_in]],
    constant Uniforms& uniforms [[buffer(BufferIndexUniforms)]]
) {
    ModelVertexOut out;
    float4 position = float4(in.position, 1.0);
    float4 worldPosition = uniforms.modelMatrix * position;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition;
    out.worldPosition = worldPosition.xyz;
    float3x3 viewRotation(uniforms.viewMatrix[0].xyz,
                           uniforms.viewMatrix[1].xyz,
                           uniforms.viewMatrix[2].xyz);
    float3 eye = -(transpose(viewRotation) * uniforms.viewMatrix[3].xyz);
    out.viewDirection = eye - worldPosition.xyz;
    // SnapshotBuilder creates a rotation-only model matrix, so its linear part preserves normals.
    float3x3 modelRotation(uniforms.modelMatrix[0].xyz,
                          uniforms.modelMatrix[1].xyz,
                          uniforms.modelMatrix[2].xyz);
    out.normal = modelRotation * in.normal;
    out.uv = in.uv;
    return out;
}

fragment float4 fragment_model(
    ModelVertexOut in [[stage_in]],
    texture2d<float> baseColorTexture [[texture(0)]],
    texture2d<float> normalTexture [[texture(1)]],
    texture2d<float> roughnessTexture [[texture(2)]],
    texture2d<float> metallicTexture [[texture(3)]],
    texture2d<float> emissiveTexture [[texture(4)]],
    texture2d<float> sky [[texture(6)]],
    texture2d<float> moonAtlas [[texture(7)]],
    sampler textureSampler [[sampler(0)]],
    depth2d<float> moonDepth [[texture(5)]],
    sampler moonComparison [[sampler(1)]],
    constant float4x4& moonMatrix [[buffer(4)]],
    constant float& sceneTime [[buffer(5)]],
    constant ModelParams& params [[buffer(BufferIndexModelParams)]],
    constant FogParameters& fog [[buffer(6)]],
    constant MoonParameters& moon [[buffer(7)]]
) {
    float3 positionDX = dfdx(in.worldPosition);
    float3 positionDY = dfdy(in.worldPosition);
    float2 uvDX = dfdx(in.uv);
    float2 uvDY = dfdy(in.uv);
    float3 baseNormal = (length(in.normal) > 0.0001) ? in.normal : cross(positionDX, positionDY);
    float3 n = length(baseNormal) > 0.0001 ? normalize(baseNormal) : float3(0.0, 0.0, 1.0);
    if (params.useNormalTexture != 0 && normalTexture.get_width() > 0) {
        float3 sampledNormal = normalTexture.sample(textureSampler, in.uv).xyz * 2.0 - 1.0;
        float determinant = uvDX.x * uvDY.y - uvDX.y * uvDY.x;
        if (abs(determinant) > 0.000001) {
            float3 tangent = (positionDX * uvDY.y - positionDY * uvDX.y) / determinant;
            float3 bitangent = (positionDY * uvDX.x - positionDX * uvDY.x) / determinant;
            tangent -= n * dot(n, tangent);
            if (length(tangent) > 0.0001) {
                tangent = normalize(tangent);
                float handedness = dot(cross(n, tangent), bitangent) < 0.0 ? -1.0 : 1.0;
                bitangent = cross(n, tangent) * handedness;
                float3 mappedNormal = float3x3(tangent, bitangent, n) * sampledNormal;
                if (length(mappedNormal) > 0.0001) {
                    n = normalize(mappedNormal);
                }
            }
        }
    }

    float4 baseColor = params.baseColorFactor;
    if (params.useBaseColorTexture != 0 && baseColorTexture.get_width() > 0) {
        baseColor *= baseColorTexture.sample(textureSampler, in.uv);
    }
    if (baseColor.a < 0.01) {
        discard_fragment();
    }
    // 0: legacy, 1: opaque fragments, 2: blended fragments.
    if ((params.alphaPass == 1 && baseColor.a < 1.0) ||
        (params.alphaPass == 2 && baseColor.a >= 1.0)) {
        discard_fragment();
    }

    float roughness = clamp(params.roughnessFactor, 0.04, 1.0);
    if (params.useRoughnessTexture != 0 && roughnessTexture.get_width() > 0) {
        // ModelIO provides separate scalar maps, not a packed glTF ORM texture.
        roughness *= roughnessTexture.sample(textureSampler, in.uv).r;
    }
    roughness = clamp(roughness, 0.04, 1.0);

    float metallic = clamp(params.metallicFactor, 0.0, 1.0);
    if (params.useMetallicTexture != 0 && metallicTexture.get_width() > 0) {
        metallic *= metallicTexture.sample(textureSampler, in.uv).r;
    }
    metallic = clamp(metallic, 0.0, 1.0);

    float3 emissive = params.emissiveFactor;
    if (params.useEmissiveTexture != 0 && emissiveTexture.get_width() > 0) {
        emissive *= emissiveTexture.sample(textureSampler, in.uv).rgb;
    }

    float visibility = moonShadow(in.worldPosition, moonMatrix, moonDepth, moonComparison);
    float3 viewDir = normalize(in.viewDirection);
    SurfaceMaterial material = {clamp(baseColor.rgb, 0.0, 1.0), roughness, metallic, 0.04};
    float3 color = shadeSurface(material, in.worldPosition, n, viewDir, visibility, sceneTime, sky, moonAtlas, fog, moon);
    color += emissive;
    // Preserve linear HDR lighting and emission for bloom and the final tone mapping pass.
    return float4(applySceneFog(color, in.worldPosition, fog), baseColor.a);
}
