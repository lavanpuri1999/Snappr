import Cocoa
import ApplicationServices
import Carbon.HIToolbox

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: ArmController?
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ note: Notification) {
        ensureAccessibilityPermission()
        setupStatusItem()
        controller = ArmController(statusItem: statusItem)
        controller?.start()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "○ Snappr"
        item.button?.toolTip = "Snappr — double-tap Ctrl to arm"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Snappr", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Double-tap Ctrl to arm · Esc to stop",
                                action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        for mi in menu.items where mi.action != nil { mi.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - Permissions

func ensureAccessibilityPermission() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let opts = [key: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(opts)
}

// MARK: - Arm controller

final class ArmController {
    private var armed = false
    private var lastCtrlTapAt: TimeInterval = 0
    private let doubleTapWindow: TimeInterval = 0.4
    private var pasteboardWatcher: PasteboardWatcher?
    private var hud: ArmedHUD?
    private var eventTap: CFMachPort?
    private weak var statusItem: NSStatusItem?

    init(statusItem: NSStatusItem?) { self.statusItem = statusItem }

    func start() {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
                 | (1 << CGEventType.keyDown.rawValue)

        let cb: CGEventTapCallBack = { _, type, event, ctx in
            let me = Unmanaged<ArmController>.fromOpaque(ctx!).takeUnretainedValue()
            me.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: cb,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            fputs("Snappr: failed to create event tap. Did you grant Accessibility permission?\n", stderr)
            return
        }

        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .flagsChanged {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            // 59 = left Ctrl, 62 = right Ctrl
            guard keyCode == 59 || keyCode == 62 else { return }
            let ctrlDown = event.flags.contains(.maskControl)
            if ctrlDown {
                if armed {
                    // While armed, any Ctrl press disarms.
                    DispatchQueue.main.async { [weak self] in self?.disarm() }
                    lastCtrlTapAt = 0
                    return
                }
                let now = Date().timeIntervalSince1970
                if now - lastCtrlTapAt < doubleTapWindow {
                    DispatchQueue.main.async { [weak self] in self?.arm() }
                    lastCtrlTapAt = 0
                } else {
                    lastCtrlTapAt = now
                }
            }
        } else if type == .keyDown && armed {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if Int(keyCode) == kVK_Escape {
                DispatchQueue.main.async { [weak self] in self?.disarm() }
            }
        }
    }

    private func arm() {
        armed = true
        statusItem?.button?.title = "● Snappr"
        hud = ArmedHUD()
        hud?.show()
        pasteboardWatcher = PasteboardWatcher { [weak self] in self?.handleNewImage() }
        pasteboardWatcher?.start()
    }

    private func disarm() {
        armed = false
        statusItem?.button?.title = "○ Snappr"
        pasteboardWatcher?.stop()
        pasteboardWatcher = nil
        hud?.hide()
        hud = nil
    }

    private func handleNewImage() {
        if shouldAutoPaste() {
            synthesizePaste()
            hud?.flash("Pasted")
        } else {
            hud?.flash("On clipboard · ⌘V to paste")
        }
    }
}

// MARK: - Pasteboard watcher

final class PasteboardWatcher {
    private var lastChangeCount: Int
    private var timer: Timer?
    private let onImage: () -> Void

    init(onImage: @escaping () -> Void) {
        self.onImage = onImage
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        // NSPasteboard has no change-notification API; polling is the documented approach.
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        let types = pb.types ?? []
        let imageTypes: Set<NSPasteboard.PasteboardType> = [.png, .tiff]
        if !types.isEmpty && !imageTypes.isDisjoint(with: Set(types)) {
            onImage()
        }
    }
}

// MARK: - Focus check

func shouldAutoPaste() -> Bool {
    let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    if Terminals.bundleIDs.contains(frontID) { return true }
    return focusedElementIsEditable()
}

func focusedElementIsEditable() -> Bool {
    let system = AXUIElementCreateSystemWide()
    var focusedRef: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef)
    guard status == .success, let focused = focusedRef else { return false }
    let el = focused as! AXUIElement

    var roleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
    if let r = roleRef as? String,
       r == kAXTextFieldRole || r == kAXTextAreaRole || r == kAXComboBoxRole {
        return true
    }

    var editableRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(el, "AXEditable" as CFString, &editableRef) == .success,
       let b = editableRef as? Bool, b {
        return true
    }

    var settable: DarwinBoolean = false
    AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &settable)
    return settable.boolValue
}

// MARK: - Paste synthesis

// Terminals intercept Cmd+V themselves and only paste clipboard *text*. The TUI
// running inside (e.g. Claude Code) listens for Ctrl+V and reads NSPasteboard
// itself. So for terminals we send Ctrl+V; for everything else, Cmd+V.
//
// Wrapped in an enum because top-level `let` in main.swift is initialized in
// source order — and our top-level code calls `app.run()` which never returns,
// so any top-level constant declared after it would never be initialized.
enum Terminals {
    static let bundleIDs: Set<String> = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper"
    ]
}

func synthesizePaste() {
    let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    let useCtrl = Terminals.bundleIDs.contains(frontID)
    postPaste(useCtrl: useCtrl)
}

private func postPaste(useCtrl: Bool) {
    let src = CGEventSource(stateID: .combinedSessionState)
    let v = CGKeyCode(kVK_ANSI_V)
    let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
    let up   = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
    let mod: CGEventFlags = useCtrl ? .maskControl : .maskCommand
    down?.flags = mod
    up?.flags = mod
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

// MARK: - Floating HUD

final class ArmedHUD {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var defaultText = "Listening · Esc to stop"
    private var flashWorkItem: DispatchWorkItem?

    func show() {
        let size = NSSize(width: 220, height: 44)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(x: screen.midX - size.width/2, y: screen.minY + 80)

        let p = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let host = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        host.material = .hudWindow
        host.blendingMode = .behindWindow
        host.state = .active
        host.wantsLayer = true
        host.layer?.cornerRadius = 22
        host.layer?.masksToBounds = true

        let dot = PulsingDot(frame: NSRect(x: 16, y: 14, width: 16, height: 16))
        host.addSubview(dot)

        let lbl = NSTextField(labelWithString: defaultText)
        lbl.frame = NSRect(x: 40, y: 12, width: 170, height: 20)
        lbl.font = .systemFont(ofSize: 12, weight: .medium)
        lbl.textColor = .labelColor
        lbl.backgroundColor = .clear
        lbl.isBezeled = false
        host.addSubview(lbl)
        label = lbl

        p.contentView = host
        p.orderFrontRegardless()
        panel = p
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        label = nil
    }

    func flash(_ text: String) {
        guard let label else { return }
        flashWorkItem?.cancel()
        label.stringValue = text
        let item = DispatchWorkItem { [weak self] in
            self?.label?.stringValue = self?.defaultText ?? ""
        }
        flashWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }
}

final class PulsingDot: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        let dot = CAShapeLayer()
        dot.path = CGPath(ellipseIn: bounds, transform: nil)
        dot.fillColor = NSColor.systemRed.cgColor
        layer?.addSublayer(dot)

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.35
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        dot.add(pulse, forKey: "pulse")
    }
}
