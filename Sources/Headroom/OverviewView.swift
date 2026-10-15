import HeadroomCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 28) {
                    ArcGauge(fraction: model.snapshot.primaryVolume?.freeFraction ?? 0)
                        .frame(width: 210, height: 210)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(freeTitle)
                            .font(.system(size: 56, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.cream)
                            .contentTransition(.numericText())
                        Text(freeDetail)
                            .foregroundStyle(Theme.dim)
                        Text(Narrative.glance(snapshot: model.snapshot, reviewBytes: model.reviewBytes))
                            .foregroundStyle(Theme.cream.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                        if model.scanning {
                            Text(model.scanProgress)
                                .foregroundStyle(Theme.brass)
                        }
                    }
                    .font(.system(size: 14))
                }

                if model.scan?.partial == true {
                    DeskCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Some folders were skipped")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.cream)
                            Text("macOS blocked some folders, so they were left unread. Denying those prompts is fine. The map stays on this Mac either way.")
                                .foregroundStyle(Theme.dim)
                                .font(.system(size: 13))
                        }
                    }
                }

                SectionLabel(text: "Strata")
                if let scan = model.scan {
                    StrataStrip(slices: NodeFind.strata(scan.tree, home: NSHomeDirectory()))
                    legend(scan.tree)
                } else {
                    DeskCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("The disk is not mapped yet")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.cream)
                            Text("Mapping reads folder sizes. It does not delete, and it does not download iCloud files.")
                                .foregroundStyle(Theme.dim)
                            Button("Map home") { model.scanHome() }
                                .buttonStyle(BrassButtonStyle())
                        }
                    }
                }

                SectionLabel(text: "Volumes")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(model.snapshot.volumes) { volume in
                        DeskCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(volume.name).foregroundStyle(Theme.cream).font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    Pill(text: volume.isInternal ? "Internal" : "External", tint: volume.isInternal ? Theme.sage : Theme.sky)
                                }
                                Text("\(ByteFormat.string(volume.freeBytes)) free · \(ByteFormat.string(volume.purgeableBytes)) purgeable")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.dim)
                                Meter(title: "Used", value: ByteFormat.string(volume.usedBytes), fraction: 1 - volume.freeFraction, tint: Theme.brass)
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    DeskCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: "This week")
                            let card = postcard
                            ForEach(card.lines, id: \.self) { line in
                                Text(line).foregroundStyle(Theme.cream).font(.system(size: 14))
                            }
                        }
                    }
                    DeskCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: "Since last map")
                            if deltas.isEmpty {
                                Text("Map the same folder twice and the changes show up here.")
                                    .foregroundStyle(Theme.dim)
                            } else {
                                ForEach(deltas.prefix(5)) { delta in
                                    HStack {
                                        Text(delta.name).foregroundStyle(Theme.cream)
                                        Spacer()
                                        Text(ByteFormat.signedDelta(delta.bytes))
                                            .foregroundStyle(delta.bytes >= 0 ? Theme.coral : Theme.sage)
                                            .monospacedDigit()
                                    }
                                    .font(.system(size: 13))
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private var freeTitle: String {
        guard let volume = model.snapshot.primaryVolume else { return "—" }
        return ByteFormat.string(volume.freeBytes)
    }

    private var freeDetail: String {
        guard let volume = model.snapshot.primaryVolume else { return "Waiting for the disk" }
        return "free of \(ByteFormat.string(volume.totalBytes)) on \(volume.name). \(ByteFormat.string(volume.purgeableBytes)) can be purged by macOS."
    }

    private var postcard: Postcard {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return PostcardMaker.make(
            now: Date(),
            lastScan: model.scan,
            previous: model.previousScan,
            freedThisWeek: ScanStore.freed(since: weekAgo)
        )
    }

    private var deltas: [PathDelta] {
        guard let scan = model.scan, let previous = model.previousScan, scan.root == previous.root else { return [] }
        return ScanDiff.topLevelDeltas(previous: previous.tree, current: scan.tree)
    }

    private func legend(_ node: FileNode) -> some View {
        let slices = NodeFind.strata(node, home: NSHomeDirectory())
        return HStack(spacing: 12) {
            ForEach(slices, id: \.0) { slice in
                HStack(spacing: 6) {
                    Circle().fill(Theme.color(for: slice.0)).frame(width: 7, height: 7)
                    Text(slice.0.title).foregroundStyle(Theme.dim)
                }
                .font(.system(size: 11))
            }
        }
    }
}
