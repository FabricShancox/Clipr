import Foundation

/// Edits to a session's step list as pure value transforms. Keeping file access out of here is
/// what lets Review's undo be "swap the old manifest back" and keeps every rule unit-testable.
enum ManifestEditor {
    /// SwiftUI `onMove` semantics: `toOffset` is an index into the original array before which the
    /// moved steps land. Implemented here rather than via SwiftUI's `Array.move` so this file has
    /// no UI dependency.
    static func moving(_ m: SessionManifest, fromOffsets: IndexSet, toOffset: Int) -> SessionManifest {
        let offsets = fromOffsets.filter { $0 < m.steps.count }
        guard !offsets.isEmpty, (0...m.steps.count).contains(toOffset) else { return m }
        var steps = m.steps
        let moving = offsets.map { steps[$0] }
        let before = offsets.filter { $0 < toOffset }.count
        for index in offsets.reversed() { steps.remove(at: index) }
        steps.insert(contentsOf: moving, at: toOffset - before)
        var result = m
        result.steps = steps
        return result
    }

    static func settingCaption(_ caption: String?, forStep id: UUID, in m: SessionManifest) -> SessionManifest {
        guard let index = m.steps.firstIndex(where: { $0.id == id }) else { return m }
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = m
        result.steps[index].caption = (trimmed?.isEmpty ?? true) ? nil : trimmed
        return result
    }

    /// `.full` is stored as `nil`, the same as a never-sized step, so there is one way to say Full
    /// and "set to Full" on such a step is recognisably no change.
    static func settingImageSize(_ size: ImageSize?, forSteps ids: Set<UUID>, in m: SessionManifest) -> SessionManifest {
        let stored = size == .full ? nil : size
        var result = m
        for index in result.steps.indices where ids.contains(result.steps[index].id) {
            result.steps[index].imageSize = stored
        }
        return result
    }

    /// Each step moves from its own size (nil counts as Full) along small < medium < large < full,
    /// stopping at either end rather than wrapping.
    static func steppingImageSize(by delta: Int, forSteps ids: Set<UUID>, in m: SessionManifest) -> SessionManifest {
        let order = ImageSize.allCases
        var result = m
        for index in result.steps.indices where ids.contains(result.steps[index].id) {
            let current = order.firstIndex(of: result.steps[index].imageSize ?? .full) ?? order.count - 1
            let next = order[min(max(current + delta, 0), order.count - 1)]
            result.steps[index].imageSize = next == .full ? nil : next
        }
        return result
    }

    static func removing(ids: Set<UUID>, from m: SessionManifest) -> (SessionManifest, [RemovedStep]) {
        var removed: [RemovedStep] = []
        var kept: [StepRecord] = []
        for (index, step) in m.steps.enumerated() {
            if ids.contains(step.id) { removed.append(RemovedStep(record: step, index: index)) } else { kept.append(step) }
        }
        var result = m
        result.steps = kept
        return (result, removed)
    }

    /// Inserting in ascending original index restores each step to exactly where it was, because
    /// every earlier removed step has already been put back by the time a later one is inserted.
    static func restoring(_ removed: [RemovedStep], into m: SessionManifest) -> SessionManifest {
        var result = m
        for item in removed.sorted(by: { $0.index < $1.index }) {
            result.steps.insert(item.record, at: min(item.index, result.steps.count))
        }
        return result
    }
}
