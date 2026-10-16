//
//  LRUCache.swift
//  Moonforge
//
//  Created by Codex on 19.03.26.
//

import Foundation
import os

// MARK: - LRU Cache

/// Потокобезопасный LRU кэш на основе словаря и двунаправленного списка
final class LRUCache<Key: Hashable, Value> {
    private final class Node {
        let key: Key
        var value: Value
        // Узлы удерживаются словарём и связью next; слабая prev исключает цикл удержания.
        weak var prev: Node?
        var next: Node?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    private struct State {
        var storage: [Key: Node] = [:]
        var head: Node?
        var tail: Node?
    }

    private let _capacity: Int
    var capacity: Int { _capacity }
    private let lock = OSAllocatedUnfairLock<State>(uncheckedState: State())

    init(capacity: Int) {
        precondition(capacity > 0, "LRUCache capacity must be greater than 0")
        self._capacity = capacity
    }

    var count: Int {
        lock.withLockUnchecked { $0.storage.count }
    }

    func value(forKey key: Key) -> Value? {
        lock.withLockUnchecked { state in
            guard let node = state.storage[key] else { return nil }
            moveToHead(node, state: &state)
            return node.value
        }
    }

    func setValue(_ value: Value, forKey key: Key) {
        _ = setValueReportingEviction(value, forKey: key)
    }

    /// Reports an actual capacity eviction within the same locked insertion.
    func setValueReportingEviction(_ value: Value, forKey key: Key) -> Bool {
        lock.withLockUnchecked { state in
            if let node = state.storage[key] {
                node.value = value
                moveToHead(node, state: &state)
                return false
            }

            let node = Node(key: key, value: value)
            state.storage[key] = node
            insertAtHead(node, state: &state)

            if state.storage.count > capacity {
                removeTail(state: &state)
                return true
            }
            return false
        }
    }

    func removeValue(forKey key: Key) {
        lock.withLockUnchecked { state in
            removeValue(forKey: key, state: &state)
        }
    }

    /// Удаляет элементы, ключи которых удовлетворяют предикату.
    ///
    /// Семантика конкурентности:
    /// - Снимок ключей: на момент вызова создаётся снимок существующих ключей под замком.
    /// - Вычисление предиката: предикат выполняется вне лока, что исключает взаимные блокировки
    ///   при повторном обращении (reentrancy) к методам кэша (`count`, `value(forKey:)`).
    /// - Удаление: совпавшие ключи удаляются атомарно под замком. Если ключ был удалён или вытеснен
    ///   параллельным потоком между снимком и удалением, операция безопасно пропускает его.
    ///   Если значение для ключа было конкурентно обновлено, удаление подчиняется естественному
    ///   порядку линеаризации (обновление -> последующее удаление).
    func removeValues(where shouldRemove: (Key) -> Bool) {
        let keysToEvaluate = lock.withLockUnchecked { Array($0.storage.keys) }
        let keysToRemove = keysToEvaluate.filter(shouldRemove)
        guard !keysToRemove.isEmpty else { return }
        lock.withLockUnchecked { state in
            for key in keysToRemove {
                removeValue(forKey: key, state: &state)
            }
        }
    }

    private func removeValue(forKey key: Key, state: inout State) {
        guard let node = state.storage[key] else { return }

        let prev = node.prev
        let next = node.next
        prev?.next = next
        next?.prev = prev

        if state.tail === node {
            state.tail = prev
        }
        if state.head === node {
            state.head = next
        }

        state.storage[key] = nil
    }

    func removeAll() {
        lock.withLockUnchecked { state in
            state.storage.removeAll()
            state.head = nil
            state.tail = nil
        }
    }

    // MARK: - Linked List Helpers

    private func insertAtHead(_ node: Node, state: inout State) {
        node.prev = nil
        node.next = state.head
        state.head?.prev = node
        state.head = node
        if state.tail == nil {
            state.tail = node
        }
    }

    private func moveToHead(_ node: Node, state: inout State) {
        guard state.head !== node else { return }

        let prev = node.prev
        let next = node.next
        prev?.next = next
        next?.prev = prev

        if state.tail === node {
            state.tail = prev
        }

        node.prev = nil
        node.next = state.head
        state.head?.prev = node
        state.head = node
    }

    private func removeTail(state: inout State) {
        guard let tail = state.tail else { return }
        state.storage[tail.key] = nil
        let prev = tail.prev
        prev?.next = nil
        state.tail = prev
        if state.tail == nil {
            state.head = nil
        }
        tail.prev = nil
        tail.next = nil
    }
}

// MARK: - Sendable Conformance

extension LRUCache: @unchecked Sendable where Key: Sendable, Value: Sendable {}
