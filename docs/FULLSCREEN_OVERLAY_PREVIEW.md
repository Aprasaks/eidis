# JARVIS — full-screen summoning proof of concept (2026-11-19 KST)

## What is running

- This is a separate **preview**, not a replacement of `~/Applications/JARVIS.app` (still v3.8.4).
- Worktree: `~/Documents/JARVIS-FULLSCREEN-PREVIEW`.
- Bundle: `dist/JARVIS.app`, with preview identifier `dev.dechive.jarvis.fullscreen-preview` (set when packaged for local testing).
- Source: user's 10-second, 1920 × 1080, 24fps MP4 at `~/Downloads/iQhSN3U_pOuZs8eXZ6jAsA.mp4`. The source video was not edited or deleted.
- Loop asset: 1280 × 720 HEVC with transparency, approximately 13 MB, in `macos/Resources/Art/JARVIS_Activation_Alpha_HEVC.mov`.

## How to summon / dismiss

1. Launch `dist/JARVIS.app` once. Keep the preview process running.
2. From any desktop app, press **Command + Option + J** to summon the full-screen darkening overlay.
3. Press **Escape** or **Command + Option + J** again to dismiss it.
4. Use the JARVIS Dock icon to reopen the legacy settings/work window if hidden.

The overlay is an `NSPanel` across the active display, with the user's actual desktop dimmed beneath the alpha-enabled video. Existing app windows are ordered out, not closed. No external AI calls or microphone sessions are initiated by summoning.

## Verification completed on user's Mac

- Existing source Python tests plus new overlay contracts: 137 passed.
- Swift compiled; preview app packaged and ad-hoc code signature verified.
- On-screen full-display panel confirmed at 1512 × 982 logical points, covering the Mac main display.
- Two screenshots 3 seconds apart: 25.1% changed pixels in central sampling region. A later, separate pair (after multiple 10-second loop periods): 18.2% changed. This supports continued real playback, but does not establish glitch-free looping under all workloads.
- Live Mac keyboard simulation: Escape dismissed the panel; Command-Option-J summoned it; pressing shortcut again dismissed it.
- Production ElevenLabs Keychain auto-lookup is skipped for the separate preview bundle ID; production service and credentials were not altered.
- Original installed JARVIS v3.8.4 unchanged; earlier Blender source worktree remains unchanged.

## Not yet implemented or proven

- Speaking "자비스" / wake word detection is NOT implemented. The overlay is hotkey-triggered only.
- The current clip is not yet an exact match to the user's fixed reference image. Some dark halo/transparency artifacts may remain at the outside edge of the glow.
- We have not instrumented frame drops, GPU power, or performance across long sessions or multiple displays.
- Pressing the hotkey while a full-screen game is active may be subject to macOS window/space behaviors and is untested.

The user's fixed design reference should remain the only target for subsequent visual refinement; do not generate substitute artwork.

## Final preview packaging and focus reliability

- Installed separate copy at `~/Applications/JARVIS Fullscreen Preview.app`, bundle ID `dev.dechive.jarvis.fullscreen-preview`; confirmed from installed copy that the panel appears across the entire active display.
- AppKit `NSPanel.hidesOnDeactivate = false` is required; otherwise the full-screen panel disappears when another app becomes active. Tested with Chrome in front and panel still onscreen.
- To prevent window ordering failures, `window.alphaValue` remains 1 and SwiftUI contents fade in using 0.36s animation; Reduce Motion disables the transition.
- Reverified a manually sent Command+Option+J after dismissal creates the full-screen panel from the **installed** app. Escape and hotkey closing tested earlier in the same preview implementation.
- **Wake-word/microphone wake-up is not part of this preview.**
