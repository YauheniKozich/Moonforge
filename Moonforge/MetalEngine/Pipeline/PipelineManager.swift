//
//  PipelineManager.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import Metal
import QuartzCore
import Foundation
import os.lock

// MARK: - Pipeline Manager

/// Manages render pipeline states
public final class PipelineManager {
    private let device: MTLDevice

    private let pipelineCache = LRUCache<String, MTLRenderPipelineState>(
        capacity: MetalConfiguration.Performance.pipelineCacheLimit
    )
    private let depthStencilLock = OSAllocatedUnfairLock(initialState: [MTLPixelFormat: MTLDepthStencilState]())

    // MARK: - Initialization

    public init(device: MTLDevice) {
        self.device = device
    }

    public var pipelineCacheCount: Int {
        pipelineCache.count
    }

    // MARK: - Pipeline Creation

    /// Create pipeline state from shader functions
    func createPipeline(
        vertexFunction: MTLFunction,
        fragmentFunction: MTLFunction,
        vertexDescriptor: MTLVertexDescriptor,
        colorPixelFormat: MTLPixelFormat,
        depthStencilPixelFormat: MTLPixelFormat,
        sampleCount: Int = 1
    ) throws -> MTLRenderPipelineState {
        let cacheKey = makePipelineKey(
            vertexFunction: vertexFunction,
            fragmentFunction: fragmentFunction,
            vertexDescriptor: vertexDescriptor,
            colorPixelFormat: colorPixelFormat,
            depthStencilPixelFormat: depthStencilPixelFormat,
            sampleCount: sampleCount
        )

        if let cached = pipelineCache.value(forKey: cacheKey) {
            return cached
        }

        // Use factory for descriptor creation
        let descriptor = PipelineDescriptorFactory.makeRenderPipelineDescriptor(
            vertexFunction: vertexFunction,
            fragmentFunction: fragmentFunction,
            vertexDescriptor: vertexDescriptor,
            colorPixelFormat: colorPixelFormat,
            depthStencilPixelFormat: depthStencilPixelFormat,
            sampleCount: sampleCount
        )

        let pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        pipelineCache.setValue(pipelineState, forKey: cacheKey)
        _ = depthStencilState(for: depthStencilPixelFormat)
        return pipelineState
    }

    func depthStencilState(for pixelFormat: MTLPixelFormat) -> MTLDepthStencilState? {
        // Проверяем кэш первым
        let cached = depthStencilLock.withLock { $0[pixelFormat] }

        if let cached = cached {
            return cached
        }

        // Создаём новый state
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        let state = device.makeDepthStencilState(descriptor: depthDesc)

        // Кэшируем результат
        if let state {
            depthStencilLock.withLock { $0[pixelFormat] = state }
        }
        return state
    }

    private func makePipelineKey(
        vertexFunction: MTLFunction,
        fragmentFunction: MTLFunction,
        vertexDescriptor: MTLVertexDescriptor,
        colorPixelFormat: MTLPixelFormat,
        depthStencilPixelFormat: MTLPixelFormat,
        sampleCount: Int
    ) -> String {
        // Предварительно рассчитываем ёмкость для уменьшения аллокаций
        var result = ""
        result.reserveCapacity(256)
        
        result.append("v:")
        result.append(vertexFunction.name)
        result.append("|f:")
        result.append(fragmentFunction.name)
        result.append("|c:")
        result.append(String(colorPixelFormat.rawValue))
        result.append("|d:")
        result.append(String(depthStencilPixelFormat.rawValue))
        result.append("|samples:\(sampleCount)")

        // Находим максимальный индекс атрибута для оптимизации
        var maxAttrIndex = 0
        for i in 0..<31 {
            if let attr = vertexDescriptor.attributes[i], attr.format != .invalid {
                maxAttrIndex = i
            }
        }
        
        // Добавляем только до максимального атрибута
        for i in 0...maxAttrIndex {
            guard let attr = vertexDescriptor.attributes[i],
                  attr.format != .invalid else { continue }
            result.append("|a")
            result.append(String(i))
            result.append(":f")
            result.append(String(attr.format.rawValue))
            result.append("o")
            result.append(String(attr.offset))
            result.append("b")
            result.append(String(attr.bufferIndex))
        }

        // Находим максимальный индекс layout для оптимизации
        var maxLayoutIndex = 0
        for i in 0..<31 {
            if let layout = vertexDescriptor.layouts[i], layout.stride != 0 {
                maxLayoutIndex = i
            }
        }
        
        // Добавляем только до максимального layout
        for i in 0...maxLayoutIndex {
            guard let layout = vertexDescriptor.layouts[i],
                  layout.stride != 0 else { continue }
            result.append("|l")
            result.append(String(i))
            result.append(":s")
            result.append(String(layout.stride))
            result.append("r")
            result.append(String(layout.stepRate))
            result.append("f")
            result.append(String(layout.stepFunction.rawValue))
        }

        return result
    }

    // MARK: - Cleanup

    func cleanup() {
        pipelineCache.removeAll()
        depthStencilLock.withLock { $0.removeAll() }
    }
}
