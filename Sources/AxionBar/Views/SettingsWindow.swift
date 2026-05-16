import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class SettingsWindow {
    private var panel: NSWindow?

    func show(controller: StatusBarController) {
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = SettingsView(controller: controller)
        let newPanel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        newPanel.title = "Axion 设置"
        newPanel.contentView = NSHostingView(rootView: contentView)
        newPanel.center()
        newPanel.makeKeyAndOrderFront(nil)
        self.panel = newPanel
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var controller: StatusBarController
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HotkeyTabView(controller: controller)
                .tabItem { Label("技能热键", systemImage: "keyboard") }
                .tag(0)

            AccessibilityTabView()
                .tabItem { Label("辅助功能权限", systemImage: "lock.shield") }
                .tag(1)
        }
        .frame(minWidth: 460, minHeight: 350)
    }
}

// MARK: - Hotkey Tab

struct HotkeyTabView: View {
    @ObservedObject var controller: StatusBarController
    @State private var showAddSheet = false
    @State private var selectedSkill: BarSkillSummary?
    @State private var isRecordingHotkey = false
    @State private var recordedModifiers: NSEvent.ModifierFlags = []
    @State private var recordedKeyCode: UInt16 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if controller.hotkeyConfigManager.bindings.isEmpty {
                Text("未配置热键绑定。点击下方按钮添加。")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            } else {
                List {
                    ForEach(controller.hotkeyConfigManager.bindings) { binding in
                        HStack {
                            switch binding.action {
                            case .skill(let name):
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.blue)
                                Text(name)
                            case .task(let desc):
                                Image(systemName: "text.cursor")
                                    .foregroundColor(.orange)
                                Text(desc)
                            }
                            Spacer()
                            Text(binding.displayString)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(4)
                            Button {
                                controller.hotkeyConfigManager.removeBinding(id: binding.id)
                                controller.restartHotkeyService()
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("添加热键绑定") {
                    showAddSheet = true
                }
                .disabled(controller.availableSkills.isEmpty)
            }
        }
        .padding()
        .sheet(isPresented: $showAddSheet) {
            AddHotkeySheet(
                controller: controller,
                isPresented: $showAddSheet,
                selectedSkill: $selectedSkill,
                isRecordingHotkey: $isRecordingHotkey,
                recordedModifiers: $recordedModifiers,
                recordedKeyCode: $recordedKeyCode
            )
        }
    }
}

// MARK: - Add Hotkey Sheet

struct AddHotkeySheet: View {
    @ObservedObject var controller: StatusBarController
    @Binding var isPresented: Bool
    @Binding var selectedSkill: BarSkillSummary?
    @Binding var isRecordingHotkey: Bool
    @Binding var recordedModifiers: NSEvent.ModifierFlags
    @Binding var recordedKeyCode: UInt16
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("添加热键绑定")
                .font(.headline)

            // Step 1: Select skill
            VStack(alignment: .leading) {
                Text("1. 选择技能:")
                    .font(.subheadline)
                Picker("技能", selection: $selectedSkill) {
                    Text("请选择...").tag(nil as BarSkillSummary?)
                    ForEach(controller.availableSkills, id: \.name) { skill in
                        Text(skill.name).tag(skill as BarSkillSummary?)
                    }
                }
                .pickerStyle(.menu)
            }

            // Step 2: Record hotkey
            VStack(alignment: .leading) {
                Text("2. 按下热键组合:")
                    .font(.subheadline)

                if isRecordingHotkey {
                    HotkeyRecorderView(
                        modifiers: $recordedModifiers,
                        keyCode: $recordedKeyCode,
                        isRecording: $isRecordingHotkey
                    )
                } else {
                    Button("开始录制") {
                        isRecordingHotkey = true
                        recordedModifiers = []
                        recordedKeyCode = 0
                    }
                }
            }
            .disabled(selectedSkill == nil)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                Button("取消") { isPresented = false }
                Spacer()
                Button("保存") {
                    guard let skill = selectedSkill,
                          recordedKeyCode > 0,
                          !recordedModifiers.isEmpty else { return }

                    let result = controller.hotkeyConfigManager.addBinding(
                        action: .skill(name: skill.name),
                        modifiers: recordedModifiers,
                        keyCode: recordedKeyCode
                    )
                    if result != nil {
                        controller.restartHotkeyService()
                        isPresented = false
                    } else {
                        errorMessage = "该热键组合已被占用，请选择其他组合。"
                    }
                }
                .disabled(selectedSkill == nil || recordedKeyCode == 0 || recordedModifiers.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

// MARK: - Hotkey Recorder

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var modifiers: NSEvent.ModifierFlags
    @Binding var keyCode: UInt16
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.onKeyRecorded = { mods, code in
            modifiers = mods
            keyCode = code
            isRecording = false
        }
        return view
    }

    func updateNSView(_: HotkeyRecorderNSView, context: Context) {}
}

final class HotkeyRecorderNSView: NSView {
    var onKeyRecorded: ((NSEvent.ModifierFlags, UInt16) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !mods.isEmpty else { return }
        onKeyRecorded?(mods, event.keyCode)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: 13),
        ]
        let str = NSAttributedString(string: "请按下热键组合...", attributes: attrs)
        let rect = bounds
        str.draw(in: CGRect(
            x: rect.minX,
            y: rect.midY - 8,
            width: rect.width,
            height: 20
        ))
    }
}

// MARK: - Accessibility Tab

struct AccessibilityTabView: View {
    @State private var hasPermission = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(hasPermission ? .green : .orange)

            Text(hasPermission ? "辅助功能权限已授权" : "辅助功能权限未授权")
                .font(.headline)

            Text("全局热键需要辅助功能权限才能监听其他应用中的按键事件。")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 350)

            if !hasPermission {
                Button("打开系统偏好设置") {
                    GlobalHotkeyService.promptAccessibilityPermission()
                }
                .buttonStyle(.borderedProminent)
            }

            Button("重新检查") {
                hasPermission = GlobalHotkeyService.checkAccessibilityPermission()
            }
        }
        .padding()
        .onAppear {
            hasPermission = GlobalHotkeyService.checkAccessibilityPermission()
        }
    }
}
