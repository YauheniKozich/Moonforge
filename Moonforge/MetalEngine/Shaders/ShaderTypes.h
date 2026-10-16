//
//  ShaderTypes.h
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// MARK: - Vertex

typedef struct {
    vector_float3 position;
    vector_float3 color;
} Vertex;

typedef struct {
    vector_float3 position;
    vector_float3 normal;
    vector_float2 uv;
} VertexModel;

// MARK: - Uniforms

typedef struct {
    matrix_float4x4 modelMatrix;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 projectionMatrix;
} Uniforms;

// Linear HDR color/density, base height/falloff/sky distance, world camera position.
typedef struct {
    vector_float4 colorDensity;
    vector_float4 height;
    vector_float4 cameraPosition;
} FogParameters;

typedef struct {
    vector_float4 panoramaMapping; // xy: offset, z: cylindrical vertical scale, w: moon intensity
    vector_float4 direction; // xyz: direction to moon, w: angular radius
    vector_float4 textureRegion; // xy: original disk center, zw: texture radii
} MoonParameters;

// MARK: - Model Params

typedef struct {
    uint32_t useBaseColorTexture;
    uint32_t useNormalTexture;
    uint32_t useRoughnessTexture;
    uint32_t useMetallicTexture;
    uint32_t useEmissiveTexture;
    uint32_t alphaPass;
    uint32_t padding1;
    uint32_t padding2;
    vector_float4 baseColorFactor;
    vector_float3 emissiveFactor;
    float roughnessFactor;
    float metallicFactor;
    vector_float3 padding3;
} ModelParams;

// MARK: - Buffer Indices

typedef enum BufferIndex {
    BufferIndexVertices     = 0,
    BufferIndexColors       = 1,
    BufferIndexUniforms     = 2,
    BufferIndexModelParams  = 3
} BufferIndex;

// MARK: - Attribute Indices

typedef enum AttributeIndex {
    AttributeIndexPosition  = 0,
    AttributeIndexColor     = 1,
    AttributeIndexNormal    = 2,
    AttributeIndexUV        = 3
} AttributeIndex;

#endif /* ShaderTypes_h */
