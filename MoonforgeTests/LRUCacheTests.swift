//
//  LRUCacheTests.swift
//  MoonforgeTests
//
//  Created by Codex on 19.03.26.
//

import XCTest
@testable import Moonforge

final class LRUCacheTests: XCTestCase {
    func testEvictsLeastRecentlyUsed() {
        let cache = LRUCache<String, Int>(capacity: 2)
        cache.setValue(1, forKey: "A")
        cache.setValue(2, forKey: "B")

        _ = cache.value(forKey: "A") // A becomes most recently used
        cache.setValue(3, forKey: "C") // should evict B

        XCTAssertNotNil(cache.value(forKey: "A"))
        XCTAssertNil(cache.value(forKey: "B"))
        XCTAssertNotNil(cache.value(forKey: "C"))
    }

    func testReadUpdatesRecency() {
        let cache = LRUCache<String, Int>(capacity: 2)
        cache.setValue(10, forKey: "X")
        cache.setValue(20, forKey: "Y")

        _ = cache.value(forKey: "X")
        cache.setValue(30, forKey: "Z")

        XCTAssertNotNil(cache.value(forKey: "X"))
        XCTAssertNil(cache.value(forKey: "Y"))
    }

    func testRemoveValuesReentrancy() {
        let cache = LRUCache<String, Int>(capacity: 5)
        cache.setValue(1, forKey: "A")
        cache.setValue(2, forKey: "B")
        cache.setValue(3, forKey: "C")

        XCTAssertEqual(cache.count, 3)

        cache.removeValues { key in
            _ = cache.count
            _ = cache.value(forKey: "A")
            return key == "B"
        }

        XCTAssertEqual(cache.count, 2)
        XCTAssertNil(cache.value(forKey: "B"))
        XCTAssertNotNil(cache.value(forKey: "A"))
        XCTAssertNotNil(cache.value(forKey: "C"))
    }
}
