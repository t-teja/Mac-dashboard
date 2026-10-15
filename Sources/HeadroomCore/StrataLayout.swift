import Foundation

public enum StrataLayout {
    /// Horizontal icicle. Each row is one level deeper. Child widths follow allocated size.
    public static func icicle(
        node: FileNode,
        width: Double,
        rowHeight: Double,
        rows: Int,
        gap: Double = 3
    ) -> [LayoutRect] {
        guard width > 1, rowHeight > 1, rows > 0, node.allocatedBytes > 0 else { return [] }
        var output: [LayoutRect] = []
        func place(_ node: FileNode, x: Double, y: Double, width: Double, depth: Int) {
            let rect = LayoutRect(
                x: x, y: y, width: max(0, width), height: rowHeight,
                path: node.path, name: node.name, bytes: node.allocatedBytes, depth: depth
            )
            output.append(rect)
            let nextDepth = depth + 1
            guard nextDepth < rows, width > gap else { return }
            let children = node.children.filter { $0.allocatedBytes > 0 }
            let total = children.reduce(Int64(0)) { $0 + $1.allocatedBytes }
            guard total > 0 else { return }
            let gapTotal = gap * Double(max(0, children.count - 1))
            let usable = max(0, width - gapTotal)
            var cursor = x
            for child in children {
                let share = usable * Double(child.allocatedBytes) / Double(total)
                if share >= 1 {
                    place(child, x: cursor, y: y + rowHeight + gap, width: share, depth: nextDepth)
                }
                cursor += share + gap
            }
        }
        place(node, x: 0, y: 0, width: width, depth: 0)
        return output
    }
}

public enum ScanDiff {
    public static func topLevelDeltas(previous: FileNode, current: FileNode, minimumBytes: Int64 = 50_000_000) -> [PathDelta] {
        let old = Dictionary(uniqueKeysWithValues: previous.children.map { ($0.path, $0) })
        var deltas: [PathDelta] = []
        var seen = Set<String>()
        for child in current.children where !child.path.hasSuffix("::other") {
            seen.insert(child.path)
            let before = old[child.path]?.allocatedBytes ?? 0
            let delta = child.allocatedBytes - before
            if abs(delta) >= minimumBytes {
                deltas.append(PathDelta(path: child.path, name: child.name, bytes: delta))
            }
        }
        for child in previous.children where !seen.contains(child.path) && !child.path.hasSuffix("::other") {
            if child.allocatedBytes >= minimumBytes {
                deltas.append(PathDelta(path: child.path, name: child.name, bytes: -child.allocatedBytes))
            }
        }
        return deltas.sorted { abs($0.bytes) > abs($1.bytes) }
    }
}

public enum TreeEdit {
    /// Drops removed paths and subtracts their size from ancestors. Missing paths are left alone.
    public static func removing(paths: Set<String>, from node: FileNode) -> FileNode {
        var copy = node
        if paths.contains(node.path) {
            copy.children = []
            copy.allocatedBytes = 0
            return copy
        }
        var next: [FileNode] = []
        var removed: Int64 = 0
        for child in node.children {
            if paths.contains(child.path) {
                removed += child.allocatedBytes
                continue
            }
            let edited = removing(paths: paths, from: child)
            removed += child.allocatedBytes - edited.allocatedBytes
            if edited.allocatedBytes > 0 || !edited.children.isEmpty {
                next.append(edited)
            }
        }
        copy.children = next.sorted { $0.allocatedBytes > $1.allocatedBytes }
        copy.allocatedBytes = max(0, copy.allocatedBytes - removed)
        return copy
    }
}
