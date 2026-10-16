# MetalEngine Thread Safety Guide

## Overview

MetalEngine uses a **double-buffering with snapshot** approach for thread-safe rendering. The core principle is:

> **Main thread mutates state → Render thread reads immutable snapshots**

This document describes the thread safety model for each component.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Main Thread                               │
│  - User input (gestures, UI controls)                           │
│  - Geometry switching                                           │
│  - Camera controls (orbit, pan, zoom)                           │
│  - Setup/teardown                                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ State mutations
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    @MainActor Components                         │
│  - BaseRenderer                                                 │
│  - GeometryRegistry (actor)                                     │
│  - TextureRepository (actor)                                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Build snapshot
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SnapshotBuilder                               │
│  - Pure function (no locks, no mutations)                       │
│  - Creates immutable RenderSnapshot                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Atomic swap
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    snapshotLock (OSAllocatedUnfairLock)          │
│  - Protects RenderSnapshot?                                     │
│  - Atomic read/write                                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Read snapshot
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Render Thread                               │
│  - Metal draw calls (MTKViewDelegate.draw(in:))                 │
│  - Reads immutable snapshot                                     │
│  - No locks needed during rendering                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component Thread Safety

### BaseRenderer

| Method/Property | Thread Context | Notes |
|-----------------|----------------|-------|
| `init` | Main thread | Standard initialization |
| `setup(metalView:)` | Main thread | @MainActor |
| `switchGeometry(to:)` | Main thread | @MainActor |
| `rotate(x:y:)` | Main thread | @MainActor, delegates to CameraComponent |
| `orbit/pan/zoom/resetCamera` | Main thread | @MainActor, delegates to CameraComponent |
| `draw(drawable:renderPassDescriptor:)` | Render thread | nonisolated, reads snapshot |
| `cleanup()` | Any thread | nonisolated, thread-safe via cleanupLock |
| `updateRenderSnapshot(for:)` | Main thread | Builds snapshot |
| `updateDrawableSize(_:)` | Any thread | Thread-safe via renderStateLock |
| `debugInfo` | Main thread | @MainActor |
| `availableGeometries` | Main thread | @MainActor |
| `currentGeometryName` | Main thread | @MainActor |

**Locks used:**
- `snapshotLock`: Protects RenderSnapshot? (atomic swap)
- `cleanupLock`: Guarantees single cleanup execution
- `renderStateLock`: Protects mutable render state

---

### CameraComponent

| Method/Property | Thread Context | Notes |
|-----------------|----------------|-------|
| `orbit(deltaX:deltaY:)` | Any thread | Thread-safe via stateLock |
| `pan(deltaX:deltaY:)` | Any thread | Thread-safe via stateLock |
| `zoom(delta:)` | Any thread | Thread-safe via stateLock |
| `reset()` | Any thread | Thread-safe via stateLock |
| `getStateSnapshot()` | Any thread | Returns value type copy |
| `computeViewMatrix(for:)` | Any thread | Pure function, no locks |
| `computeViewMatrix()` | Any thread | Convenience method |

**Locks used:**
- `stateLock`: OSAllocatedUnfairLock<CameraState>

**Design notes:**
- `CameraState` is a value type (struct) — safe to copy between threads
- Double-buffering: mutations happen on Main thread, reads on render thread

---

### RenderTimingComponent

| Method/Property | Thread Context | Notes |
|-----------------|----------------|-------|
| `update()` | Render thread | Called every frame |
| `deltaTime` | Any thread | Read-only accessor |
| `currentFPS` | Any thread | Updated once per second |
| `reset()` | Any thread | Thread-safe |

**Locks used:**
- `stateLock`: OSAllocatedUnfairLock<State>

**Design notes:**
- Delta time is capped at 2x target frame time to avoid jumps after suspension
- FPS is calculated over 1-second windows

---

### SnapshotBuilder

| Method/Property | Thread Context | Notes |
|-----------------|----------------|-------|
| `build(...)` | Any thread | Pure function, stateless |

**Locks used:** None

**Design notes:**
- This is a stateless struct — all methods are pure functions
- No thread safety concerns

---

### TextureRepository (Actor)

| Method/Property | Thread Context | Notes |
|-----------------|----------------|-------|
| `init` | Any thread | Creates placeholder synchronously |
| `loadTexture()` | Any thread | Async, actor-isolated |
| `getTexture()` | Any thread | Async, actor-isolated |
| `isUsingFallback()` | Any thread | Async, actor-isolated |
| `cleanup()` | Any thread | Async, actor-isolated |
| `placeholder` | Any thread | **nonisolated** — synchronous access |

**Actor isolation:**
- All mutable state is protected by actor boundary
- `placeholder` is `nonisolated` — safe for synchronous access without `await`

**Design notes:**
- Actor-based design allows async texture loading without blocking
- Placeholder texture is created during init and never mutated

---

### GeometryRegistry (Actor)

| Method/Property | Thread Context | Notes |
|-----------------|----------------|-------|
| `register(_:factory:)` | Main thread | @MainActor (via GeometrySwitching) |
| `make(_:device:)` | Main thread | @MainActor (via GeometrySwitching) |
| `names` | Main thread | @MainActor |

**Actor isolation:**
- All methods are actor-isolated
- Called from @MainActor context (BaseRenderer)

**Design notes:**
- Actor design allows future async geometry loading if needed
- Currently used synchronously from @MainActor context

---

### PipelineManager

| Method/Property | Thread Context | Notes |
|-----------------|----------------|-------|
| `init(device:)` | Any thread | Standard initialization |
| `createPipeline(...)` | Main thread | Called during setup |
| `depthStencilState(for:)` | Main thread | Called during setup |
| `pipelineCacheCount` | Any thread | Thread-safe via LRUCache |
| `cleanup()` | Any thread | Thread-safe |

**Locks used:**
- Internal LRUCache uses OSAllocatedUnfairLock

**Design notes:**
- Pipeline creation is typically done during setup (Main thread)
- Cache is thread-safe for concurrent access

---

### LRUCache

| Method/Property | Thread Context | Notes |
|-----------------|----------------|-------|
| `value(forKey:)` | Any thread | Thread-safe |
| `setValue(_:forKey:)` | Any thread | Thread-safe |
| `removeAll()` | Any thread | Thread-safe |
| `count` | Any thread | Thread-safe |

**Locks used:**
- `lock`: OSAllocatedUnfairLock<State>

**Design notes:**
- Doubly linked list + dictionary for O(1) get/set
- Lock protects all mutations

---

## Best Practices

### 1. Never Access @MainActor Properties from Render Thread

```swift
// ❌ WRONG - data race
nonisolated func draw(...) {
    let geometry = currentGeometry  // Direct access to @MainActor property
}

// ✅ CORRECT - use snapshot
nonisolated func draw(...) {
    guard let snapshot = snapshotLock.withLock({ $0 }) else { return }
    // Use snapshot data...
}
```

### 2. Always Use SnapshotBuilder for RenderSnapshot

```swift
// ❌ WRONG - manual snapshot construction
let snapshot = RenderSnapshot(
    rotation: rotation,
    uniforms: uniforms,
    ...
)

// ✅ CORRECT - use builder
let snapshot = SnapshotBuilder.build(
    geometry: geometry,
    pipeline: pipeline,
    rotation: rotation,
    ...
)
```

### 3. Actor Properties Require `await`

```swift
// ❌ WRONG - missing await
let texture = textureRepository.texture

// ✅ CORRECT
let texture = await textureRepository.getTexture()

// ✅ CORRECT - nonisolated property
let placeholder = textureRepository.placeholder  // No await needed
```

### 4. Thread-Safe State Access

```swift
// ✅ CameraComponent - returns value type copy
let cameraState = cameraComponent.getStateSnapshot()
let viewMatrix = cameraComponent.computeViewMatrix(for: cameraState)

// ✅ RenderTimingComponent - thread-safe accessors
let deltaTime = timingComponent.deltaTime
let fps = timingComponent.currentFPS
```

### 5. Cleanup is Idempotent

```swift
// ✅ Safe to call multiple times
renderer.cleanup()
renderer.cleanup()  // No-op, guaranteed by cleanupLock
```

---

## Debugging Thread Safety Issues

### Common Symptoms

1. **Crash with "Simultaneous accesses"**
   - Check for direct access to @MainActor properties from nonisolated context
   - Verify all mutations go through locks or actor boundaries

2. **Stale data in render loop**
   - Ensure snapshot is rebuilt before each frame
   - Verify atomic swap via snapshotLock

3. **Actor reentrancy issues**
   - Check for `await` boundaries in actor methods
   - Consider using `nonisolated` for read-only accessors

### Tools

1. **Thread Sanitizer** (Xcode → Edit Scheme → Diagnostics → Thread Sanitizer)
   - Detects data races at runtime

2. **OSAllocatedUnfairLock Callbacks**
   ```swift
   let lock = OSAllocatedUnfairLock(initialState: State())
   lock.withLock { state in
       // Add breakpoint here to inspect lock holder
   }
   ```

3. **Actor Isolation Warnings**
   - Enable strict concurrency checking in build settings
   - Xcode will warn about actor isolation violations

---

## Migration Guide (Pre-Refactoring → Post-Refactoring)

### Old Code

```swift
// Direct property access
func draw(...) {
    let geometry = currentGeometry  // @MainActor property
    let pipeline = currentPipeline
    // ...
}
```

### New Code

```swift
// Snapshot-based access
nonisolated func draw(...) {
    guard let snapshot = snapshotLock.withLock({ $0 }) else { return }
    // Use snapshot data - no @MainActor hop needed
}
```

### Old Code

```swift
// Manual matrix calculation
func updateViewMatrix() -> float4x4 {
    renderStateLock.withLock { _ in
        computeViewMatrix(for: cameraState)
    }
}
```

### New Code

```swift
// Delegate to CameraComponent
func updateViewMatrix() -> float4x4 {
    let state = cameraComponent.getStateSnapshot()
    return cameraComponent.computeViewMatrix(for: state)
}
```

---

## Summary

| Component | Concurrency Model | Key Lock/Mechanism |
|-----------|------------------|---------------------|
| BaseRenderer | @MainActor + snapshot | snapshotLock, cleanupLock, renderStateLock |
| CameraComponent | Lock-based | OSAllocatedUnfairLock<CameraState> |
| RenderTimingComponent | Lock-based | OSAllocatedUnfairLock<State> |
| SnapshotBuilder | Stateless | None (pure functions) |
| TextureRepository | Actor | Actor isolation + nonisolated placeholder |
| GeometryRegistry | Actor | Actor isolation |
| PipelineManager | Lock-based (internal) | LRUCache with OSAllocatedUnfairLock |
| LRUCache | Lock-based | OSAllocatedUnfairLock<State> |

**Key Principle:** Main thread mutates, render thread reads snapshots. No exceptions.
