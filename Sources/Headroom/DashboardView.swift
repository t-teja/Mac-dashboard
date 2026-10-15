import HeadroomCore
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            rail
            Rectangle().fill(Theme.line).frame(width: 1)
            VStack(spacing: 0) {
                page
                BinBar()
            }
        }
        .background(Theme.ink)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1040, minHeight: 700)
        .toolbarBackground(Theme.ink, for: .windowToolbar)
        .toolbarColorScheme(.dark, for: .windowToolbar)
        .sheet(isPresented: $model.showConfirm) {
            CleanupSheet()
                .environment(model)
        }
        .sheet(isPresented: $model.showResults) {
            ResultsSheet()
                .environment(model)
        }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Headroom")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.brass)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            ForEach(DeskPage.allCases) { page in
                Button {
                    model.page = page
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: page.symbol)
                            .frame(width: 16)
                        Text(page.title)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 13, weight: model.page == page ? .semibold : .regular))
                    .foregroundStyle(model.page == page ? Theme.ink : Theme.cream)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(model.page == page ? Theme.brass : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 188)
        .background(Theme.ink)
    }

    @ViewBuilder private var page: some View {
        Group {
            switch model.page {
            case .overview: OverviewView()
            case .disk: DiskView()
            case .performance: PerformanceView()
            case .images: ImagesView()
            case .duplicates: DuplicatesView()
            case .apps: AppsView()
            case .cloud: CloudView()
            case .settings: SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct BinBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.bin.isEmpty ? "The bin is empty" : "\(model.bin.count) in the bin")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.cream)
                Text(model.bin.isEmpty ? "Add something, then review it. Nothing leaves until you confirm." : ByteFormat.string(model.binBytes) + " staged")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            if let banner = model.banner {
                Text(banner)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            Button("Export script") { model.exportScript() }
                .buttonStyle(QuietButtonStyle())
                .disabled(model.bin.isEmpty)
            Button("Review") { model.showConfirm = true }
                .buttonStyle(BrassButtonStyle())
                .disabled(model.bin.isEmpty || model.removing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.raised)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}
