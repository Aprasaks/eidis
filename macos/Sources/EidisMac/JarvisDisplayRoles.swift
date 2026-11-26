import AppKit
import CoreGraphics

/// Verified household layout: left LG = JARVIS HOME, ultrawide = work,
/// built-in MacBook display = secondary. Names are persisted instead of
/// transient display IDs so reconnecting a monitor does not reshuffle roles.
enum JarvisDisplayRoles {
    enum Role: String, CaseIterable {
        case home, work, secondary
        var preferenceKey: String { "jarvis.display.role.\(rawValue).name" }
    }

    static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(number.uint32Value) != 0
    }

    static func screen(for role: Role, in screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        guard !screens.isEmpty else { return nil }
        if let saved = UserDefaults.standard.string(forKey: role.preferenceKey),
           let matched = screens.first(where: { $0.localizedName == saved }),
           // A role temporarily bound to the MacBook when undocked must not
           // override a physical external monitor after reconnecting at home.
           !(role != .secondary && isBuiltIn(matched) && hasHouseholdArrangement(in: screens)) {
            return matched
        }

        let external = screens.filter { !isBuiltIn($0) }
        switch role {
        case .home:
            return external.first(where: { $0.localizedName.localizedCaseInsensitiveContains("LG FULL HD") })
                ?? external.sorted(by: { $0.frame.midX < $1.frame.midX }).first
                ?? NSScreen.main ?? screens.first
        case .work:
            return external.first(where: { $0.localizedName.localizedCaseInsensitiveContains("TFG30F20W") })
                ?? external.max(by: { ($0.frame.width / max($0.frame.height, 1)) <
                                     ($1.frame.width / max($1.frame.height, 1)) })
                ?? NSScreen.main ?? screens.first
        case .secondary:
            return screens.first(where: isBuiltIn)
                ?? NSScreen.main ?? screens.first
        }
    }

    /// The three-screen arrangement is opt-in through the physical setup,
    /// never triggered merely because a MacBook is opened alone.
    static func hasHouseholdArrangement(in screens: [NSScreen] = NSScreen.screens) -> Bool {
        guard screens.contains(where: isBuiltIn),
              screens.contains(where: { $0.localizedName.localizedCaseInsensitiveContains("LG FULL HD") }),
              screens.contains(where: { $0.localizedName.localizedCaseInsensitiveContains("TFG30F20W") })
        else { return false }
        return true
    }

    /// Register actual connected display names only when the role has not
    /// already been explicitly selected. Never change system monitor layout.
    static func registerConnectedScreens() {
        let isHomeDesk = hasHouseholdArrangement()
        for role in Role.allCases {
            // Only register external monitor roles when physically connected.
            // A MacBook-only session may resolve a fallback without persisting it.
            if role != .secondary && !isHomeDesk { continue }
            guard let match = screen(for: role) else { continue }
            let saved = UserDefaults.standard.string(forKey: role.preferenceKey)
            if let saved, saved != match.localizedName,
               role == .secondary || !NSScreen.screens.contains(where: {
                   $0.localizedName == saved && isBuiltIn($0)
               }) {
                continue // Preserve the user's explicit external display choice.
            }
            if saved == match.localizedName { continue }
            UserDefaults.standard.set(match.localizedName, forKey: role.preferenceKey)
            NSLog("JARVIS: display role %@ -> %@ frame=%@",
                  role.rawValue, match.localizedName, NSStringFromRect(match.frame))
        }
    }
}
