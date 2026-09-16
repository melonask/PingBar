import SwiftUI

#if canImport(AppKit)
    import AppKit

    /// The bitmap type each platform renders in SwiftUI images.
    public typealias PlatformImage = NSImage
#else
    import UIKit

    /// The bitmap type each platform renders in SwiftUI images.
    public typealias PlatformImage = UIImage
#endif

extension Image {
    /// Builds a SwiftUI image from the host platform's bitmap type.
    init(platformImage: PlatformImage) {
        #if canImport(AppKit)
            self.init(nsImage: platformImage)
        #else
            self.init(uiImage: platformImage)
        #endif
    }
}

enum PlatformPasteboard {
    static func copy(_ value: String) {
        #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        #else
            UIPasteboard.general.string = value
        #endif
    }
}

public extension AppAppearance {
    /// The SwiftUI color scheme this appearance maps to, or `nil` to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

public extension StatusLevel {
    var color: Color {
        switch self {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        }
    }
}
