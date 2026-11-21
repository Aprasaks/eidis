import AppKit

/// One place for keyboard focus decisions while JARVIS is visible.
/// Normal typing wins over bare Space. Option-Space is an explicit voice key.
enum JarvisVoiceShortcutPolicy {
    static func handles(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        composerEditing: Bool,
        browserEditing: Bool,
        isRepeat: Bool = false
    ) -> Bool {
        guard keyCode == 49, !isRepeat else { return false }
        let relevant = modifiers.intersection([.option, .command, .control, .shift])
        if relevant == [.option] { return true }
        if relevant.isEmpty && !composerEditing && !browserEditing { return true }
        return false
    }
}
