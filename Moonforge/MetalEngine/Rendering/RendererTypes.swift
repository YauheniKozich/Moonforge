//
//  RendererTypes.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Metal
import MetalKit
import os

// MARK: - Buffer Indices

enum BufferIndex: Int {
    case vertices = 0
    case colors   = 1
    case uniforms = 2
    case modelParams = 3
}

// MARK: - Uniforms

/// Must match ShaderTypes.h exactly.
struct Uniforms: Sendable {
    var modelMatrix:      matrix_float4x4
    var viewMatrix:       matrix_float4x4
    var projectionMatrix: matrix_float4x4
}

/// Must match FogParameters in ShaderTypes.h (three aligned float4 values).
struct FogParameters: Sendable {
    var colorDensity: SIMD4<Float>
    var height: SIMD4<Float>
    var cameraPosition: SIMD4<Float>
}

/// Must match MoonParameters in ShaderTypes.h.
struct MoonParameters: Sendable {
    var panoramaMapping: SIMD4<Float> // xy: offset, z: cylindrical vertical scale, w: moon intensity
    var direction: SIMD4<Float> // xyz: direction to moon, w: angular radius
    var textureRegion: SIMD4<Float> // xy: original disk center, zw: texture radii
}

struct ModelParams: Sendable {
    var useBaseColorTexture: UInt32
    var useNormalTexture: UInt32
    var useRoughnessTexture: UInt32
    var useMetallicTexture: UInt32
    var useEmissiveTexture: UInt32
    var alphaPass: UInt32
    var padding1: UInt32
    var padding2: UInt32
    var baseColorFactor: SIMD4<Float>
    var emissiveFactor: SIMD3<Float>
    var roughnessFactor: Float
    var metallicFactor: Float
    var padding3: SIMD3<Float>
}

// MARK: - FPS State

struct FPSState {
    var lastTime:   CFTimeInterval = 0
    var frameCount: Int = 0
}
