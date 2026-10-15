import HeadroomCore
import SwiftUI

struct CleanupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            Text("Review the bin")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.cream)
            Text(intro)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.bin) { item in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(item.title).foregroundStyle(Theme.cream)
                                    if item.method.isPermanent {
                                        Pill(text: "Permanent", tint: Theme.coral)
                                    }
                                }
                                Text(PathDisplay.string(item.subtitle))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.dim)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(item.bytes > 0 ? ByteFormat.string(item.bytes) : "")
                                .foregroundStyle(Theme.cream)
                                .monospacedDigit()
                            Button("Remove") { model.removeFromBin(item.id) }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.brass)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)

            ForEach(CleanupPlan.overlapNotes(model.bin), id: \.self) { note in
                Text(note).font(.system(size: 12)).foregroundStyle(Theme.brass)
            }

            if model.permanentInBin {
                Toggle("I understand the permanent items cannot be restored from the Trash", isOn: $model.acceptPermanent)
                    .foregroundStyle(Theme.cream)
            }

            HStack {
                Text(ByteFormat.string(model.binBytes))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.cream)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                Button(model.removing ? "Working…" : buttonTitle) { model.removeConfirmed() }
                    .buttonStyle(BrassButtonStyle())
                    .disabled(model.removing || model.bin.isEmpty || (model.permanentInBin && !model.acceptPermanent))
            }
        }
        .padding(24)
        .frame(width: 640)
        .background(Theme.ink)
        .preferredColorScheme(.dark)
    }

    private var intro: String {
        if model.permanentInBin {
            return "Files go to the Trash. Simulator runtimes and Docker images do not. Those stay gone unless you download them again."
        }
        return "Every file here is moved to the Trash. You can put it back. Nothing is permanently deleted."
    }

    private var buttonTitle: String {
        model.permanentInBin ? "Remove" : "Move to Trash"
    }
}

struct ResultsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What happened")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.cream)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.outcomes) { outcome in
                        HStack(alignment: .top) {
                            Image(systemName: outcome.ok ? "checkmark.circle" : "exclamationmark.circle")
                                .foregroundStyle(outcome.ok ? Theme.sage : Theme.coral)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(outcome.title).foregroundStyle(Theme.cream)
                                Text(outcome.message).font(.system(size: 12)).foregroundStyle(Theme.dim)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(BrassButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(Theme.ink)
        .preferredColorScheme(.dark)
    }
}
