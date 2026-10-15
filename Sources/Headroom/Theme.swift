import HeadroomCore
import SwiftUI

enum Theme {
    static let ink = Color(red: 0.063, green: 0.071, blue: 0.094)
    static let raised = Color(red: 0.102, green: 0.114, blue: 0.153)
    static let line = Color(red: 0.188, green: 0.204, blue: 0.255)
    static let cream = Color(red: 0.957, green: 0.937, blue: 0.902)
    static let dim = Color(red: 0.663, green: 0.635, blue: 0.584)
    static let brass = Color(red: 0.878, green: 0.659, blue: 0.290)
    static let sage = Color(red: 0.490, green: 0.808, blue: 0.627)
    static let coral = Color(red: 0.890, green: 0.420, blue: 0.353)
    static let sky = Color(red: 0.494, green: 0.714, blue: 0.839)
    static let lilac = Color(red: 0.725, green: 0.627, blue: 0.878)
    static let sand = Color(red: 0.843, green: 0.769, blue: 0.639)

    static func color(for category: DiskCategory) -> Color {
        switch category {
        case .documentsMedia: return sand
        case .developerTools: return sky
        case .codeProjects: return lilac
        case .mobileSDKs: return sage
        case .aiModels: return coral
        case .packageCaches: return brass
        case .osImages: return cream
        case .systemOther: return dim
        }
    }

    static func color(for tier: SafetyTier) -> Color {
        switch tier {
        case .safe: return sage
        case .review: return brass
        case .keep: return dim
        }
    }
}

enum DeskPage: String, CaseIterable, Identifiable {
    case overview, disk, performance, images, duplicates, apps, cloud, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .disk: return "Disk"
        case .performance: return "Performance"
        case .images: return "Images"
        case .duplicates: return "Duplicates"
        case .apps: return "Apps"
        case .cloud: return "Cloud"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "circle.circle"
        case .disk: return "square.stack.3d.up"
        case .performance: return "waveform.path.ecg"
        case .images: return "opticaldisc"
        case .duplicates: return "square.on.square"
        case .apps: return "square.grid.2x2"
        case .cloud: return "cloud"
        case .settings: return "slider.horizontal.3"
        }
    }
}
