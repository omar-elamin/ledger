import SwiftUI

enum Typography {
    static func serifBody(_ size: CGFloat = 17) -> Font {
        .system(size: size, design: .serif)
    }

    static func roundedNumber(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func smallCaps(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium)
    }
}

extension View {
    func smallCapsLabel(size: CGFloat = 13) -> some View {
        self
            .font(Typography.smallCaps(size))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(Color.ledgerTextTertiary)
    }
}
