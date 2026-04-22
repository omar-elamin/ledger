import SwiftUI
import UIKit

extension Color {
    static let ledgerBg = Color(uiColor: .init { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255, alpha: 1)
            : UIColor.white
    })

    static let ledgerTextPrimary = Color(uiColor: .init { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0xF5/255, green: 0xF5/255, blue: 0xF5/255, alpha: 1)
            : UIColor(red: 0x1A/255, green: 0x1A/255, blue: 0x1A/255, alpha: 1)
    })

    static let ledgerTextSecondary = Color(uiColor: .init { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x99/255, green: 0x99/255, blue: 0x99/255, alpha: 1)
            : UIColor(red: 0x66/255, green: 0x66/255, blue: 0x66/255, alpha: 1)
    })

    static let ledgerTextTertiary = Color(uiColor: .init { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x66/255, green: 0x66/255, blue: 0x66/255, alpha: 1)
            : UIColor(red: 0x99/255, green: 0x99/255, blue: 0x99/255, alpha: 1)
    })

    static let ledgerHairline = Color(uiColor: .init { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x2A/255, green: 0x2A/255, blue: 0x2A/255, alpha: 1)
            : UIColor(red: 0xE5/255, green: 0xE5/255, blue: 0xE5/255, alpha: 1)
    })

    static let ledgerCoachBg = Color(uiColor: .init { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x1A/255, green: 0x1A/255, blue: 0x1A/255, alpha: 1)
            : UIColor(red: 0xF8/255, green: 0xF8/255, blue: 0xF8/255, alpha: 1)
    })

    static let ledgerUserBg = Color(uiColor: .init { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x22/255, green: 0x22/255, blue: 0x22/255, alpha: 1)
            : UIColor(red: 0xF0/255, green: 0xF0/255, blue: 0xF0/255, alpha: 1)
    })
}
