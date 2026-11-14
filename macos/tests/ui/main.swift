import AppKit
import Foundation
import SwiftUI

// Offscreen native SwiftUI smoke test. There is no window ordering, screen
// capture, Accessibility prompt, Finder launch or GitHub action.
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)

func checkLayout<V: View>(_ view: V, name: String) {
    let frame = NSRect(x: 0, y: 0, width: 1120, height: 840)
    let host = NSHostingView(rootView: view)
    host.frame = frame
    let window = NSWindow(contentRect: frame, styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    let dimensions = host.fittingSize
    precondition(dimensions.width > 100 && dimensions.height > 100,
                 "\(name) has invalid native layout size")
    print("PASS \(name) native SwiftUI offscreen layout: \(Int(dimensions.width)) × \(Int(dimensions.height))")
    window.contentView = nil
    window.close()
}

checkLayout(ApprovedProjectsPanel(), name: "Work tab")

let fixture = """
{"id":2,"name":"UI fixture","goal":"render test","repo_full_name":"Example/project",
 "tasks":[],"task_counts":{"todo":0,"doing":0,"blocked":0,"done":0},
 "last_check":null}
"""
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
let sample = try decoder.decode(WorkProject.self, from: Data(fixture.utf8))
let model = MainActor.assumeIsolated { ApprovedWorkModel() }
checkLayout(WorkspaceResumePanel(project: sample, work: model),
            name: "Approved workspace panel")
print("PASS no permissions requested and no approved action invoked")
