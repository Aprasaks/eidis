import AppKit
import Foundation

@main struct VoiceShortcutSmoke {
    static func main() {
        func can(_ flags: NSEvent.ModifierFlags = [],
                 composer: Bool = false,
                 web: Bool = false,
                 code: UInt16 = 49,
                 repeated: Bool = false) -> Bool {
            JarvisVoiceShortcutPolicy.handles(keyCode:code,modifiers:flags,
                composerEditing:composer,browserEditing:web,isRepeat:repeated)
        }
        precondition(can())
        precondition(can([.option]))
        precondition(can([.option],composer:true))
        precondition(can([.option],web:true))
        precondition(!can([],composer:true))
        precondition(!can([],web:true))
        precondition(!can([.shift],web:false))
        precondition(!can([.command]))
        precondition(!can([.control]))
        precondition(!can([.option,.shift]))
        precondition(!can([],code:50))
        precondition(!can([],repeated:true))
        precondition(!can([.option],repeated:true))
        print("PASS: voice shortcuts never swallow Space while typing; Option-Space works with browser focus")
    }
}
