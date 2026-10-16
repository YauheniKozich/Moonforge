//
//  CubeGeometry.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Metal
import MetalKit

// MARK: - Cube Geometry

private struct CubeVertex {
    var position: SIMD3<Float>
    var color: SIMD3<Float>
}

final class CubeGeometry: GeometrySource {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int
    let indexType: MTLIndexType = .uint16
    let vertexDescriptor: MTLVertexDescriptor
    let primitiveType: MTLPrimitiveType = .triangle
    let shaderNames: (vertex: String, fragment: String) = (
        MetalConfiguration.Shaders.vertex,
        MetalConfiguration.Shaders.fragment
    )
    let submeshes: [SubmeshGeometry]
    let preferredCameraDistance: Float? = nil

    init(device: MTLDevice, size: Float = MetalConfiguration.Geometry.cubeSize) throws {
        let s = size / 2

        let positions: [SIMD3<Float>] = [
            [-s, -s,  s], [ s, -s,  s], [ s,  s,  s], [-s,  s,  s], // Front
            [-s, -s, -s], [ s, -s, -s], [ s,  s, -s], [-s,  s, -s], // Back
            [-s, -s, -s], [-s, -s,  s], [-s,  s,  s], [-s,  s, -s], // Left
            [ s, -s, -s], [ s, -s,  s], [ s,  s,  s], [ s,  s, -s], // Right
            [-s,  s, -s], [ s,  s, -s], [ s,  s,  s], [-s,  s,  s], // Top
            [-s, -s, -s], [ s, -s, -s], [ s, -s,  s], [-s, -s,  s]  // Bottom
        ]

        let faceColors: [SIMD3<Float>] = [
            [1, 0, 0],
            [0, 1, 0],
            [0, 0, 1],
            [1, 1, 0],
            [1, 0, 1],
            [0, 1, 1]
        ]

        var colors: [SIMD3<Float>] = []
        colors.reserveCapacity(24)
        for c in faceColors {
            for _ in 0..<4 { colors.append(c) }
        }

        var vertices: [CubeVertex] = []
        vertices.reserveCapacity(24)
        for i in 0..<positions.count {
            vertices.append(CubeVertex(position: positions[i], color: colors[i]))
        }

        var indices: [UInt16] = []
        indices.reserveCapacity(36)
        for i in 0..<6 {
            let base = UInt16(i * 4)
            indices.append(contentsOf: [base, base + 1, base + 2, base + 2, base + 3, base])
        }

        let vertexLength = vertices.count * MemoryLayout<CubeVertex>.stride
        let indexLength = indices.count * MemoryLayout<UInt16>.stride

        guard let vbuf = device.makeBuffer(bytes: vertices, length: vertexLength, options: [.storageModeShared]) else {
            throw MetalError.bufferCreationFailed
        }
        vbuf.label = "CubeVertices"

        guard let ibuf = device.makeBuffer(bytes: indices, length: indexLength, options: [.storageModeShared]) else {
            throw MetalError.bufferCreationFailed
        }
        ibuf.label = "CubeIndices"

        vertexBuffer = vbuf
        indexBuffer = ibuf
        indexCount = indices.count
        vertexDescriptor = CubeGeometry.makeVertexDescriptor()
        submeshes = []
    }

    private static func makeVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()

        let positionOffset = MemoryLayout<CubeVertex>.offset(of: \.position) ?? 0
        let colorOffset = MemoryLayout<CubeVertex>.offset(of: \.color) ?? 0
        let stride = MemoryLayout<CubeVertex>.stride

        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = positionOffset
        descriptor.attributes[0].bufferIndex = 0

        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = colorOffset
        descriptor.attributes[1].bufferIndex = 0

        descriptor.layouts[0].stride = stride
        descriptor.layouts[0].stepRate = 1
        descriptor.layouts[0].stepFunction = .perVertex

        return descriptor
    }
}
