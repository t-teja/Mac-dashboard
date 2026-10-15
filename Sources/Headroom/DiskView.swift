import HeadroomCore
import SwiftUI

struct DiskView: View {
    @Environment(AppModel.self) private var model
    @State private var stack: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Disk")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.cream)
                        Text(model.scanning ? model.scanProgress : "An icicle of the folder you map. Width is allocated size.")
                            .foregroundStyle(Theme.dim)
                            .font(.system(size: 13))
                    }
                    Spacer()
                    if model.scanning {
                        Button("Cancel") { model.cancelScan() }.buttonStyle(QuietButtonStyle())
                    }
                    Button("Choose folder") { model.chooseScanFolder() }.buttonStyle(QuietButtonStyle())
                    Button("Map home") { model.scanHome() }.buttonStyle(BrassButtonStyle())
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Preset.allCases) { preset in
                            Button(preset.title) { model.addPreset(preset) }
                                .buttonStyle(QuietButtonStyle())
                                .help(preset.blurb)
                        }
                    }
                }

                if let node = current {
                    breadcrumb
                    icicle(node)
                    SectionLabel(text: "Inside \(PathDisplay.shortName(node.path, fallback: node.name))")
                    ForEach(node.children) { child in
                        childRow(child)
                    }
                    let here = candidates(under: node.path)
                    if !here.isEmpty {
                        SectionLabel(text: "Reviewable here")
                        ForEach(here) { candidate in
                            candidateRow(candidate)
                        }
                    }
                } else {
                    DeskCard {
                        Text("Map home reads folder names and sizes. Denying a Documents or Photos prompt leaves that folder out. File contents stay unread, and nothing is uploaded.")
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
            .padding(28)
        }
        .onChange(of: model.scan?.root) { _, root in
            stack = root.map { [$0] } ?? []
        }
        .onAppear {
            if stack.isEmpty, let root = model.scan?.root { stack = [root] }
        }
    }

    private var current: FileNode? {
        guard let tree = model.scan?.tree else { return nil }
        let path = stack.last ?? tree.path
        return NodeFind.find(tree, path: path) ?? tree
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            ForEach(Array(stack.enumerated()), id: \.offset) { index, path in
                if index > 0 { Text("›").foregroundStyle(Theme.dim) }
                Button(PathDisplay.shortName(path, fallback: (path as NSString).lastPathComponent)) {
                    stack = Array(stack.prefix(index + 1))
                }
                .buttonStyle(.plain)
                .foregroundStyle(index == stack.count - 1 ? Theme.cream : Theme.brass)
            }
        }
        .font(.system(size: 12, weight: .medium))
    }

    private func icicle(_ node: FileNode) -> some View {
        GeometryReader { geo in
            let rects = StrataLayout.icicle(node: node, width: geo.size.width, rowHeight: 36, rows: 3, gap: 4)
            ZStack(alignment: .topLeading) {
                ForEach(rects) { rect in
                    let category = Classifier.category(for: rect.path, home: NSHomeDirectory())
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.color(for: category).opacity(rect.depth == 0 ? 0.35 : 0.9))
                        .overlay(alignment: .leading) {
                            if rect.width > 80 {
                                Text("\(PathDisplay.shortName(rect.path, fallback: rect.name))  \(ByteFormat.string(rect.bytes))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 8)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
                        .onTapGesture {
                            guard rect.depth > 0 else { return }
                            if stack.last != rect.path { stack.append(rect.path) }
                        }
                }
            }
        }
        .frame(height: 36 * 3 + 8)
    }

    private func childRow(_ child: FileNode) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.color(for: Classifier.category(for: child.path, home: NSHomeDirectory())))
                .frame(width: 8, height: 8)
            Text(PathDisplay.shortName(child.path, fallback: child.name)).foregroundStyle(Theme.cream)
            if child.containsGit { Pill(text: "git", tint: Theme.dim) }
            Spacer()
            Text(ByteFormat.string(child.allocatedBytes))
                .foregroundStyle(Theme.dim)
                .monospacedDigit()
            if child.isDirectory, !child.path.hasSuffix("::other") {
                Button("Open") {
                    stack.append(child.path)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.brass)
            }
        }
        .font(.system(size: 13))
        .padding(.vertical, 4)
    }

    private func candidateRow(_ candidate: CleanupCandidate) -> some View {
        HStack(spacing: 10) {
            Pill(text: candidate.tier.title, tint: Theme.color(for: candidate.tier))
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title).foregroundStyle(Theme.cream)
                Text(candidate.detail).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(2)
            }
            Spacer()
            Text(ByteFormat.string(candidate.bytes)).foregroundStyle(Theme.cream).monospacedDigit()
            Button("Add") { model.add(candidate.binItem()) }
                .buttonStyle(QuietButtonStyle())
        }
        .padding(.vertical, 6)
    }

    private func candidates(under path: String) -> [CleanupCandidate] {
        guard let scan = model.scan else { return [] }
        return scan.candidates.filter { $0.path == path || $0.path.hasPrefix(path + "/") }
    }
}
