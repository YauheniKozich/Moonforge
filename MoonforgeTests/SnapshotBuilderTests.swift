//
//  SnapshotBuilderTests.swift
//  MoonforgeTests
//
//  Created on 21.03.26.
//

import XCTest
import Metal
import MetalKit
@testable import Moonforge

final class SnapshotBuilderTests: XCTestCase {
    private var device: MTLDevice!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "Metal device is not available in this environment")
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    }

    override func tearDown() {
        device = nil
        super.tearDown()
    }

    func testBuildUsesObjectRotationForModelMatrixAndCameraForViewMatrix() throws {
        let geometry = try makeGeometry()
        let pipeline = try makePipelineState(vertexDescriptor: geometry.vertexDescriptor)
        let depthStencil = try XCTUnwrap(makeDepthStencilState())

        let objectRotation = SIMD3<Float>(0.25, -0.4, 0)
        let cameraState = CameraState(yaw: 0.1, pitch: -0.2, distance: 4.0, pan: SIMD2<Float>(0.5, -0.25))

        let snapshot = SnapshotBuilder.build(
            geometry: geometry,
            pipeline: pipeline,
            depthStencil: depthStencil,
            rotation: objectRotation,
            cameraState: cameraState,
            drawableSize: CGSize(width: 300, height: 200),
            sampler: nil,
            modelTextureEnabled: false,
            texture: nil
        )

        let expectedModelMatrix = float4x4.rotationX(objectRotation.x) * .rotationY(objectRotation.y) * .rotationZ(objectRotation.z)
        let expectedViewMatrix = float4x4.translation([-cameraState.pan.x, -cameraState.pan.y, -cameraState.distance])
            * (float4x4.rotationX(cameraState.pitch) * .rotationY(cameraState.yaw))

        XCTAssertTrue(snapshot.uniforms.modelMatrix.isApproximatelyEqual(to: expectedModelMatrix))
        XCTAssertTrue(snapshot.uniforms.viewMatrix.isApproximatelyEqual(to: expectedViewMatrix))
    }

    private func makeGeometry() throws -> GeometrySource {
        let vertexData: [Float] = [
            0, 0, 0, 1, 0, 0, 1, 1,
            1, 0, 0, 0, 1, 0, 1, 1,
            0, 1, 0, 0, 0, 1, 1, 1
        ]
        let indexData: [UInt16] = [0, 1, 2]

        let vertexBuffer = try XCTUnwrap(
            device.makeBuffer(bytes: vertexData, length: MemoryLayout<Float>.stride * vertexData.count)
        )
        let indexBuffer = try XCTUnwrap(
            device.makeBuffer(bytes: indexData, length: MemoryLayout<UInt16>.stride * indexData.count)
        )

        return TestGeometry(
            vertexBuffer: vertexBuffer,
            indexBuffer: indexBuffer
        )
    }

    private func makePipelineState(vertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexIn {
            float3 position [[attribute(0)]];
            float3 color [[attribute(1)]];
            float2 uv [[attribute(2)]];
        };

        struct VertexOut {
            float4 position [[position]];
        };

        vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {
            VertexOut out;
            out.position = float4(in.position, 1.0);
            return out;
        }

        fragment float4 fragment_main() {
            return float4(1.0, 1.0, 1.0, 1.0);
        }
        """

        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func makeDepthStencilState() -> MTLDepthStencilState? {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.isDepthWriteEnabled = true
        descriptor.depthCompareFunction = .less
        return device.makeDepthStencilState(descriptor: descriptor)
    }
}

private struct TestGeometry: GeometrySource {
    let preferredCameraDistance: Float? = nil
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int = 3
    let indexType: MTLIndexType = .uint16
    let primitiveType: MTLPrimitiveType = .triangle
    let shaderNames: (vertex: String, fragment: String) = (MetalConfiguration.Shaders.vertex, MetalConfiguration.Shaders.fragment)
    let submeshes: [SubmeshGeometry] = []

    let vertexDescriptor: MTLVertexDescriptor = {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = MemoryLayout<Float>.stride * 3
        descriptor.attributes[1].bufferIndex = 0
        descriptor.attributes[2].format = .float2
        descriptor.attributes[2].offset = MemoryLayout<Float>.stride * 6
        descriptor.attributes[2].bufferIndex = 0
        descriptor.layouts[0].stride = MemoryLayout<Float>.stride * 8
        return descriptor
    }()
}

private extension matrix_float4x4 {
    func isApproximatelyEqual(to other: matrix_float4x4, accuracy: Float = 0.0001) -> Bool {
        (0..<4).allSatisfy { columnIndex in
            let lhs = self[columnIndex]
            let rhs = other[columnIndex]
            return abs(lhs.x - rhs.x) <= accuracy
                && abs(lhs.y - rhs.y) <= accuracy
                && abs(lhs.z - rhs.z) <= accuracy
                && abs(lhs.w - rhs.w) <= accuracy
        }
    }
}
