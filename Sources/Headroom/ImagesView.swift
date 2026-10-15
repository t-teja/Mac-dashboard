import HeadroomCore
import SwiftUI

struct ImagesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OS images")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.cream)
                        Text("Simulator runtimes and Docker images are not in the Trash after removal. Android images and macOS installers are.")
                            .foregroundStyle(Theme.dim)
                            .font(.system(size: 13))
                    }
                    Spacer()
                    Button(model.includeDocker ? "Refresh with Docker" : "Look at Docker") {
                        model.includeDocker = true
                        model.loadImages()
                    }
                    .buttonStyle(QuietButtonStyle())
                    Button("Refresh") { model.loadImages() }
                        .buttonStyle(BrassButtonStyle())
                }
                if model.loadingImages {
                    Text("Looking…").foregroundStyle(Theme.brass)
                }
                ForEach(model.imageReport.notes, id: \.self) { note in
                    Text(note).foregroundStyle(Theme.dim).font(.system(size: 13))
                }
                if model.imageReport.items.isEmpty && !model.loadingImages {
                    DeskCard {
                        Text("Nothing listed yet. Refresh to ask simctl, and use Look at Docker only when you want the daemon queried.")
                            .foregroundStyle(Theme.dim)
                    }
                }
                ForEach(model.imageReport.items) { item in
                    DeskCard {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Pill(text: item.kind.title, tint: Theme.brass)
                                    if item.method.isPermanent { Pill(text: "Permanent", tint: Theme.coral) }
                                }
                                Text(item.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.cream)
                                Text(PathDisplay.string(item.subtitle))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.dim)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(item.bytes > 0 ? ByteFormat.string(item.bytes) : "Size unknown")
                                .foregroundStyle(Theme.cream)
                                .monospacedDigit()
                            Button("Add") { model.add(item.binItem()) }
                                .buttonStyle(QuietButtonStyle())
                        }
                    }
                }
            }
            .padding(28)
        }
        .onAppear {
            if model.imageReport.items.isEmpty && !model.loadingImages {
                model.loadImages()
            }
        }
    }
}

struct DuplicatesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Duplicates")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.cream)
                        Text("Pick folders. Headroom keeps one copy, re-hashes the others, then moves only those files to the Trash.")
                            .foregroundStyle(Theme.dim)
                            .font(.system(size: 13))
                    }
                    Spacer()
                    Button("Choose folders") { model.chooseDuplicateFolders() }
                        .buttonStyle(BrassButtonStyle())
                }
                if model.scanningDuplicates {
                    Text(model.duplicateProgress).foregroundStyle(Theme.brass)
                } else if !model.duplicateProgress.isEmpty {
                    Text(model.duplicateProgress).foregroundStyle(Theme.dim)
                }
                ForEach(model.duplicateGroups) { group in
                    DuplicateGroupCard(group: group)
                }
            }
            .padding(28)
        }
    }
}

private struct DuplicateGroupCard: View {
    @Environment(AppModel.self) private var model
    var group: DuplicateGroup
    @State private var keeper: String = ""

    var body: some View {
        DeskCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(group.files.count) copies")
                        .foregroundStyle(Theme.cream)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(ByteFormat.string(group.wastedBytes) + " extra")
                        .foregroundStyle(Theme.brass)
                }
                ForEach(group.files) { file in
                    HStack {
                        Image(systemName: keeper == file.path ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(Theme.brass)
                        Text(PathDisplay.string(file.path))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.cream)
                            .lineLimit(1)
                        Spacer()
                        Text(ByteFormat.string(file.bytes)).foregroundStyle(Theme.dim)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { keeper = file.path }
                }
                Button("Stage the other copies") {
                    model.stageDuplicates(group, keeping: keeper)
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
        .onAppear {
            if keeper.isEmpty { keeper = group.files.first?.path ?? "" }
        }
    }
}
