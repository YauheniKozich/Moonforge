import XCTest
@testable import Moonforge

final class SubmeshColorPassTests: XCTestCase {
    private struct SortSample {
        let pass: SubmeshColorPass
        let depth: Float
    }

    private func sortedKeys(_ samples: [SortSample]) -> [TransparentSubmeshSortKey] {
        TransparentSubmeshSorter.sortedKeys(
            for: samples,
            shouldInclude: { $0.pass.drawsTransparent },
            depth: \.depth
        )
    }

    func testAlphaClassificationMatchesShaderThresholds() {
        let cases: [(Float, SubmeshColorPass)] = [
            (0, .neither),
            (0.005, .neither),
            (0.01, .transparentOnly),
            (0.5, .transparentOnly),
            (0.999, .transparentOnly),
            (1, .opaqueOnly),
            (2, .opaqueOnly)
        ]

        for (alpha, expected) in cases {
            XCTAssertEqual(
                SubmeshColorPass.classify(alpha: alpha, hasActiveBaseColorTexture: false),
                expected,
                "Unexpected pass classification for alpha \(alpha)"
            )
        }
    }

    func testNonFiniteAlphaKeepsBothPasses() {
        for alpha in [Float.nan, .infinity, -.infinity] {
            XCTAssertEqual(
                SubmeshColorPass.classify(alpha: alpha, hasActiveBaseColorTexture: false),
                .both
            )
        }
    }

    func testActiveBaseColorTextureKeepsBothPasses() {
        for alpha: Float in [0, 0.005, 0.01, 0.5, 0.999, 1, 2, .nan, .infinity, -.infinity] {
            XCTAssertEqual(
                SubmeshColorPass.classify(alpha: alpha, hasActiveBaseColorTexture: true),
                .both
            )
        }
    }

    func testColorPassParticipationMatchesEachClassification() {
        let classifications: [SubmeshColorPass] = [.opaqueOnly, .transparentOnly, .both, .neither]

        XCTAssertEqual(classifications.map(\.drawsOpaque), [true, false, true, false])
        XCTAssertEqual(classifications.map(\.drawsTransparent), [false, true, true, false])
    }

    func testAllSubmeshesParticipateInTransparentPass() {
        let keys = sortedKeys([
            SortSample(pass: .transparentOnly, depth: -1),
            SortSample(pass: .both, depth: -2)
        ])

        XCTAssertEqual(keys.map(\.index), [1, 0])
    }

    func testNoSubmeshesParticipateInTransparentPass() {
        XCTAssertTrue(sortedKeys([
            SortSample(pass: .opaqueOnly, depth: -1),
            SortSample(pass: .neither, depth: -2)
        ]).isEmpty)
    }

    func testMixedPassClassesKeepOriginalSourceIndices() {
        let keys = sortedKeys([
            SortSample(pass: .opaqueOnly, depth: -10),
            SortSample(pass: .transparentOnly, depth: -3),
            SortSample(pass: .both, depth: -8),
            SortSample(pass: .neither, depth: -2)
        ])

        XCTAssertEqual(keys.map(\.index), [2, 1])
    }

    func testEqualDepthUsesSourceIndexAsTieBreaker() {
        var keys = [
            TransparentSubmeshSortKey(index: 2, depth: -4),
            TransparentSubmeshSortKey(index: 0, depth: -4),
            TransparentSubmeshSortKey(index: 1, depth: -4)
        ]

        TransparentSubmeshSorter.sort(&keys)

        XCTAssertEqual(keys.map(\.index), [0, 1, 2])
    }

    func testNegativeDepthSortsInAscendingOrder() {
        let keys = sortedKeys([
            SortSample(pass: .both, depth: -1),
            SortSample(pass: .both, depth: -10),
            SortSample(pass: .transparentOnly, depth: -2)
        ])

        XCTAssertEqual(keys.map(\.index), [1, 2, 0])
    }

    func testEmptyCollectionProducesNoKeys() {
        XCTAssertTrue(sortedKeys([]).isEmpty)
    }

    func testSingleTransparentSubmeshKeepsItsSourceIndex() {
        let keys = sortedKeys([SortSample(pass: .transparentOnly, depth: -3)])

        XCTAssertEqual(keys, [TransparentSubmeshSortKey(index: 0, depth: -3)])
    }

    func testFilteredSortMatchesPreviousFullSortForTransparentSubmeshes() {
        let samples = [
            SortSample(pass: .opaqueOnly, depth: -9),
            SortSample(pass: .transparentOnly, depth: -2),
            SortSample(pass: .both, depth: -7),
            SortSample(pass: .neither, depth: -4),
            SortSample(pass: .both, depth: -2),
            SortSample(pass: .opaqueOnly, depth: -1)
        ]
        let allKeys: [TransparentSubmeshSortKey] = samples.enumerated().map { index, sample in
            TransparentSubmeshSortKey(index: index, depth: sample.depth)
        }
        let sortedAllKeys = allKeys.sorted { lhs, rhs in
            lhs.depth == rhs.depth ? lhs.index < rhs.index : lhs.depth < rhs.depth
        }
        let previousOrder = sortedAllKeys.filter { key in
            samples[key.index].pass.drawsTransparent
        }

        XCTAssertEqual(sortedKeys(samples), previousOrder)
    }

    func testDepthIsComputedOnceOnlyForTransparentParticipants() {
        let samples: [(SubmeshColorPass, Float)] = [
            (.opaqueOnly, -1),
            (.transparentOnly, -2),
            (.both, -3),
            (.neither, -4)
        ]
        var depthEvaluationCount = 0

        let keys = TransparentSubmeshSorter.sortedKeys(
            for: samples,
            shouldInclude: { $0.0.drawsTransparent },
            depth: {
                depthEvaluationCount += 1
                return $0.1
            }
        )

        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(depthEvaluationCount, 2)
    }
}
