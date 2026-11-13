import AppKit
import ApplicationServices
import SwiftUI

/// Selected by the user; no app is inspected in the background.
struct AccessibleTargetApp: Identifiable, Hashable {
    let pid: pid_t
    let displayName: String
    let bundleID: String
    var id: Int32 { pid }
}

struct AccessibleNode: Identifiable {
    let id = UUID()
    let depth: Int
    let role: String
    let label: String
}

/// One-shot, read-only view of the selected app's accessibility tree.
///
/// Deliberately never calls AXUIElementSetAttributeValue or AXUIElementPerformAction.
/// It never asks for kAXValueAttribute, selected text or user-entered text.
@MainActor
final class AccessibilityInspector: ObservableObject {
    @Published private(set) var targets: [AccessibleTargetApp] = []
    @Published var selectedPID: pid_t = 0
    @Published private(set) var rows: [AccessibleNode] = []
    @Published private(set) var status = "앱을 선택한 다음 ‘화면 구조 읽기’를 누르세요."
    @Published private(set) var lastAppName = ""
    @Published private(set) var inspected = false

    private let maxElements = 80
    private let maxDepth = 3
    private let maxChildren = 12

    init() {
        refreshTargets()
    }

    func refreshTargets() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        targets = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                !app.isTerminated &&
                app.processIdentifier > 0 &&
                app.processIdentifier != myPID
            }
            .map { app in
                AccessibleTargetApp(pid: app.processIdentifier,
                                    displayName: app.localizedName ?? "이름 없는 앱",
                                    bundleID: app.bundleIdentifier ?? "알 수 없음")
            }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }

        if !targets.contains(where: { $0.pid == selectedPID }) {
            selectedPID = targets.first?.pid ?? 0
        }
    }

    func askForPermission() {
        // Prompt can appear only after the user's button click.
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        status = trusted
            ? "접근성 권한을 확인했습니다. 앱을 선택해 읽을 수 있습니다."
            : "macOS 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 JARVIS를 허용한 뒤 다시 확인해 주세요."
    }

    func inspectSelected() {
        rows = []
        inspected = false
        lastAppName = ""

        guard AXIsProcessTrusted() else {
            status = "접근성 권한이 없습니다. ‘권한 요청’ 버튼을 눌러 macOS에서 승인해 주세요."
            return
        }
        guard let target = targets.first(where: { $0.pid == selectedPID }) else {
            status = "대상 앱을 선택해 주세요."
            return
        }
        guard NSRunningApplication(processIdentifier: target.pid) != nil else {
            status = "선택한 앱이 종료됐습니다. 앱 목록을 새로고침해 주세요."
            refreshTargets()
            return
        }

        let app = AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        lastAppName = target.displayName
        let startingElement: AXUIElement
        if let focused = elementAttribute(app, kAXFocusedWindowAttribute as CFString) {
            startingElement = focused
        } else if let windows = elementArrayAttribute(app, kAXWindowsAttribute as CFString),
                  let first = windows.first {
            startingElement = first
        } else {
            startingElement = app
        }

        var visited = Set<CFHashCode>()
        var results: [AccessibleNode] = []
        walk(startingElement, depth: 0, visited: &visited, result: &results)
        rows = results
        inspected = true
        status = results.isEmpty
            ? "읽을 수 있는 접근성 요소가 없습니다. 일부 앱은 UI 정보를 제공하지 않습니다."
            : "\(target.displayName): \(results.count)개 UI 요소 확인 (최대 \(maxElements)개 · 깊이 \(maxDepth)). 값/입력 내용 미수집."
    }

    func clear() {
        rows = []
        lastAppName = ""
        inspected = false
        status = "읽은 화면 구조를 앱 메모리에서 지웠습니다."
    }

    private func walk(_ element: AXUIElement,
                      depth: Int,
                      visited: inout Set<CFHashCode>,
                      result: inout [AccessibleNode]) {
        guard depth <= maxDepth && result.count < maxElements else { return }
        let identity = CFHash(element)
        guard visited.insert(identity).inserted else { return }
        AXUIElementSetMessagingTimeout(element, 0.25)
        let role = stringAttribute(element, kAXRoleAttribute as CFString) ?? "Unknown"
        let subrole = stringAttribute(element, kAXSubroleAttribute as CFString) ?? ""

        // Password / input components can be sensitive. Never request their title or value.
        let privateRoles = ["AXSecureTextField", "AXTextField", "AXTextArea",
                            "AXComboBox", "AXSearchField", "AXTextView"]
        let isInput = privateRoles.contains(role) ||
                      privateRoles.contains(subrole)
        let label: String
        let namedControls = ["AXButton", "AXMenuItem", "AXMenuBarItem",
                             "AXCheckBox", "AXRadioButton", "AXTab", "AXPopUpButton"]
        if isInput {
            label = "[입력 요소: 내용 비공개]"
        } else if namedControls.contains(role) {
            // Only read UI control titles. Window titles, documents and page text
            // may contain private content; they are deliberately omitted.
            label = sanitized(stringAttribute(element, kAXTitleAttribute as CFString) ?? "")
        } else {
            label = ""
        }
        result.append(AccessibleNode(depth: depth, role: role, label: label))

        // Stay bounded to avoid blocking on very large or malformed accessibility trees.
        if depth >= maxDepth || result.count >= maxElements { return }
        guard let children = elementArrayAttribute(element, kAXChildrenAttribute as CFString) else { return }
        for child in children.prefix(maxChildren) {
            if result.count >= maxElements { break }
            walk(child, depth: depth + 1, visited: &visited, result: &result)
        }
    }

    private func sanitized(_ value: String) -> String {
        let collapsed = value
            .unicodeScalars
            .map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(140))
    }

    private func stringAttribute(_ element: AXUIElement, _ key: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success else { return nil }
        return value as? String
    }

    private func elementAttribute(_ element: AXUIElement, _ key: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success else { return nil }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // The dynamic CFTypeID was checked before bridging to AXUIElement.
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func elementArrayAttribute(_ element: AXUIElement, _ key: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }
}

struct AccessibilityPanel: View {
    @StateObject private var inspector = AccessibilityInspector()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("자비스의 눈 · UI 구조 확인", systemImage: "rectangle.on.rectangle")
                .font(.headline)
            Text("앱을 직접 선택해 버튼을 누르면 종류와 일부 버튼·메뉴 제목만 읽습니다. 문서 제목·본문·텍스트 입력값·화면 사진은 읽거나 저장하지 않습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Picker("대상 앱", selection: $inspector.selectedPID) {
                    if inspector.targets.isEmpty {
                        Text("실행 중인 앱 없음").tag(pid_t(0))
                    }
                    ForEach(inspector.targets) { target in
                        Text("\(target.displayName) (\(target.pid))").tag(target.pid)
                    }
                }
                .frame(maxWidth: 480)

                Button("앱 목록 새로고침") { inspector.refreshTargets() }
            }
            HStack(spacing: 10) {
                Button("접근성 권한 요청") { inspector.askForPermission() }
                Button("화면 구조 읽기") { inspector.inspectSelected() }
                    .disabled(inspector.selectedPID == 0)
                Button("기록 지우기") { inspector.clear() }
                    .disabled(!inspector.inspected)
            }
            Text(inspector.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            GroupBox(inspector.lastAppName.isEmpty ? "선택한 앱의 UI 구조" : "\(inspector.lastAppName) · UI 구조") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        if inspector.rows.isEmpty {
                            Text("현재 읽은 UI 요소가 없습니다.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(inspector.rows) { node in
                                HStack(spacing: 10) {
                                    Text(node.role)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.cyan)
                                        .frame(width: 140, alignment: .leading)
                                    Text(node.label.isEmpty ? "(제목 없음)" : node.label)
                                        .lineLimit(2)
                                        .font(.callout)
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                                .padding(.leading, CGFloat(node.depth) * 17)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
            }
            Text("이 화면은 UI 구조를 보는 실험입니다. 버튼 클릭, 텍스트 입력, 브라우저 조작 또는 AI 분석은 수행하지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}
