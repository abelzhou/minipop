import Cocoa
import ApplicationServices
import ServiceManagement

// MARK: - Core Logic & Translation
enum Logic {
    static func targetLang(for text: String) -> String {
        text.range(of: "\\p{Han}", options: .regularExpression) != nil ? "en" : "zh-CN"
    }

    static func parseGoogleTranslate(data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let sentences = root.first as? [[Any]] else { return nil }
        let result = sentences.compactMap { $0.first as? String }.joined()
        return result.isEmpty ? nil : result
    }

    @discardableResult
    static func translate(_ text: String, to target: String? = nil, completion: @escaping @MainActor @Sendable (Result<String, Error>) -> Void) -> URLSessionDataTask {
        // shortcut: free translate.googleapis.com gtx endpoint, switch to official API key if rate-limited on heavy batch use
        let tl = target ?? targetLang(for: text)
        var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        comps.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: tl),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]
        var req = URLRequest(url: comps.url!, timeoutInterval: 10)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        // URLSession.shared automatically uses macOS system HTTP/HTTPS/SOCKS proxy settings
        let task = URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                if let err = err as? URLError, err.code == .cancelled { return }
                if let err = err { return completion(.failure(err)) }
                guard let data = data, let res = parseGoogleTranslate(data: data) else {
                    return completion(.failure(NSError(domain: "MiniPop", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析翻译结果失败"])))
                }
                completion(.success(res))
            }
        }
        task.resume()
        return task
    }

    static func runSelfTest() -> Bool {
        assert(targetLang(for: "Hello world") == "zh-CN", "English should translate to zh-CN")
        assert(targetLang(for: "你好 world") == "en", "Text with Chinese should translate to en")
        let sample = #"[[["你好世界","Hello world",null,null,10],["！","!",null,null,1]],null,"en"]"#.data(using: .utf8)!
        assert(parseGoogleTranslate(data: sample) == "你好世界！", "Multi-sentence JSON parse failed")
        print("Self-test passed.")
        return true
    }
}

// MARK: - Floating Panel (Never steals focus)
final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}

// MARK: - Selection Reader (Pure AX API, NEVER touches NSPasteboard or simulates Cmd+C)
@MainActor
enum SelectionReader {
    static func enableEnhancedAXForFrontApp() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let appEl = AXUIElementCreateApplication(frontApp.processIdentifier)
        AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    static func readSelectedText(at mouseLocation: NSPoint) -> String? {
        enableEnhancedAXForFrontApp()

        // 1. Frontmost application focused UI element
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let appEl = AXUIElementCreateApplication(frontApp.processIdentifier)
            var focused: AnyObject?
            if AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
               let el = focused,
               let text = extractText(from: el as! AXUIElement), !text.isEmpty {
                return text
            }
        }

        // 2. System-wide focused UI element
        let sys = AXUIElementCreateSystemWide()
        var sysFocused: AnyObject?
        if AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &sysFocused) == .success,
           let el = sysFocused,
           let text = extractText(from: el as! AXUIElement), !text.isEmpty {
            return text
        }

        // 3. Element directly under mouse cursor (convert Cocoa bottom-left to Quartz top-left)
        if let primaryScreen = NSScreen.screens.first {
            let cgY = primaryScreen.frame.height - mouseLocation.y
            var hitEl: AXUIElement?
            if AXUIElementCopyElementAtPosition(sys, Float(mouseLocation.x), Float(cgY), &hitEl) == .success,
               let el = hitEl,
               let text = extractTextAndParents(from: el), !text.isEmpty {
                return text
            }
        }

        return nil
    }

    private static func extractTextAndParents(from startEl: AXUIElement) -> String? {
        var cur: AXUIElement? = startEl
        for _ in 0..<5 {
            guard let el = cur else { break }
            if let text = extractText(from: el), !text.isEmpty { return text }
            var parent: AnyObject?
            if AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parent) == .success,
               let p = parent {
                cur = (p as! AXUIElement)
            } else {
                break
            }
        }
        return nil
    }

    private static func extractText(from element: AXUIElement) -> String? {
        var selected: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
           let str = selected as? String {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        var rangeRef: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let range = rangeRef {
            var strRef: AnyObject?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, range, &strRef) == .success,
               let str = strRef as? String {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}

// MARK: - App Delegate & UI
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panel = FloatingPanel()
    private var statusItem: NSStatusItem!
    private var permMenuItem: NSMenuItem!
    private var currentText = ""
    private var translatedText = ""
    private var currentTargetLang = "zh-CN"
    private var currentAnchor: NSPoint = .zero
    private var isEnabled = true
    private var downPoint: NSPoint = .zero
    private var downTime: TimeInterval = 0
    private var lastClickTime: TimeInterval = 0
    private var workItem: DispatchWorkItem?
    private var activeTask: URLSessionDataTask?
    private var hintField: NSTextField?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        requestAccessibilityPermission()
        setupMonitors()
    }

    private func requestAccessibilityPermission() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        updateStatusIcon()
    }

    @objc private func openAccessibilitySettings() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.title = isEnabled ? "✨" : "💤"
        permMenuItem?.title = AXIsProcessTrusted() ? "✓ 辅助功能权限已开启" : "⚠️ 点击授权「辅助功能」权限…"
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self

        permMenuItem = NSMenuItem(title: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        menu.addItem(permMenuItem)
        menu.addItem(.separator())

        let toggleItem = NSMenuItem(title: "启用划词即翻", action: #selector(toggleEnabled(_:)), keyEquivalent: "e")
        toggleItem.state = .on
        menu.addItem(toggleItem)

        if #available(macOS 13.0, *) {
            let launchItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
            launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
            menu.addItem(launchItem)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 MiniPop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        updateStatusIcon()
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        isEnabled.toggle()
        sender.state = isEnabled ? .on : .off
        updateStatusIcon()
        if !isEnabled { panel.orderOut(nil) }
    }

    @available(macOS 13.0, *)
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            sender.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func setupMonitors() {
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            guard let self = self else { return }
            if event.type == .leftMouseDown {
                self.downPoint = NSEvent.mouseLocation
                self.downTime = event.timestamp
                // Pre-warm Chrome/Electron accessibility tree on mouse down so selection is ready on mouse up
                SelectionReader.enableEnhancedAXForFrontApp()
            }
            if self.panel.isVisible {
                if !NSPointInRect(NSEvent.mouseLocation, self.panel.frame) {
                    self.activeTask?.cancel()
                    self.panel.orderOut(nil)
                }
            }
        }

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self = self, self.isEnabled else { return }
            let upPoint = NSEvent.mouseLocation
            if self.panel.isVisible && NSPointInRect(upPoint, self.panel.frame) { return }

            let dist = hypot(upPoint.x - self.downPoint.x, upPoint.y - self.downPoint.y)
            let isDrag = dist > 3 && (event.timestamp - self.downTime) > 0.05
            let isMultiClick = event.clickCount >= 2 || (event.timestamp - self.lastClickTime) < 0.4
            self.lastClickTime = event.timestamp

            guard isDrag || isMultiClick else { return }

            self.workItem?.cancel()
            self.attemptReadAndTranslate(at: upPoint, retriesLeft: 2)
        }
    }

    private func attemptReadAndTranslate(at point: NSPoint, retriesLeft: Int) {
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if let text = SelectionReader.readSelectedText(at: point), !text.isEmpty, text.count <= 5000 {
                self.currentText = text
                self.translatedText = ""
                self.startInstantTranslate(at: point)
            } else if retriesLeft > 0 {
                // Retry once or twice in case Electron/Chrome needs 80ms to commit AX selection
                self.attemptReadAndTranslate(at: point, retriesLeft: retriesLeft - 1)
            }
        }
        self.workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07, execute: item)
    }

    private func startInstantTranslate(at point: NSPoint, targetLang: String? = nil) {
        activeTask?.cancel()
        currentAnchor = point
        currentTargetLang = targetLang ?? Logic.targetLang(for: currentText)
        showTranslationView(text: "正在翻译…", isDone: false, near: point)
        let query = currentText
        let tl = currentTargetLang
        activeTask = Logic.translate(query, to: tl) { [weak self] res in
            guard let self = self, self.panel.isVisible else { return }
            switch res {
            case .success(let output):
                self.translatedText = output
                self.showTranslationView(text: output, isDone: true, near: point)
            case .failure(let err):
                self.showTranslationView(text: "翻译失败: \(err.localizedDescription)", isDone: false, near: point)
            }
        }
    }

    private func makeContainer(size: NSSize) -> NSVisualEffectView {
        let v = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .vibrantDark)
        v.wantsLayer = true
        v.layer?.cornerRadius = 10
        v.layer?.masksToBounds = true
        return v
    }

    private func showTranslationView(text: String, isDone: Bool, near anchor: NSPoint) {
        let maxW: CGFloat = 360
        let pad: CGFloat = 12
        let font = NSFont.systemFont(ofSize: 13.5)
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: maxW - pad * 2, height: 1000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let textH = min(max(ceil(rect.height) + 4, 22), 260)
        let bottomH: CGFloat = isDone ? 24 : 0
        let totalW = max(min(ceil(rect.width) + pad * 2 + 8, maxW), 220)
        let totalH = textH + pad * 2 + bottomH

        let box = makeContainer(size: NSSize(width: totalW, height: totalH))

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = .white
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBordered = false
        label.frame = NSRect(x: pad, y: pad + bottomH, width: totalW - pad * 2, height: textH)
        box.addSubview(label)

        if isDone {
            let copyOverlay = NSButton(frame: NSRect(origin: .zero, size: NSSize(width: totalW, height: totalH)))
            copyOverlay.title = ""
            copyOverlay.isTransparent = true
            copyOverlay.isBordered = false
            copyOverlay.target = self
            copyOverlay.action = #selector(onCopyCard)
            copyOverlay.toolTip = "点击复制译文"
            box.addSubview(copyOverlay)

            let hint = NSTextField(labelWithString: "点击复制译文")
            hint.font = .systemFont(ofSize: 11)
            hint.textColor = NSColor.white.withAlphaComponent(0.55)
            hint.frame = NSRect(x: pad, y: 6, width: 90, height: 16)
            box.addSubview(hint)
            self.hintField = hint

            let langBtn = NSButton(frame: NSRect(x: totalW - pad - 122, y: 4, width: 50, height: 20))
            langBtn.title = "中/英"
            langBtn.bezelStyle = .recessed
            langBtn.isBordered = false
            langBtn.font = .systemFont(ofSize: 11, weight: .medium)
            langBtn.contentTintColor = NSColor.white.withAlphaComponent(0.85)
            langBtn.target = self
            langBtn.action = #selector(onToggleLang)
            langBtn.toolTip = currentTargetLang == "en" ? "切换为翻译成中文" : "切换为翻译成英文"
            box.addSubview(langBtn)

            let searchBtn = NSButton(frame: NSRect(x: totalW - pad - 68, y: 4, width: 68, height: 20))
            searchBtn.title = "🔍 搜原文"
            searchBtn.bezelStyle = .recessed
            searchBtn.isBordered = false
            searchBtn.font = .systemFont(ofSize: 11, weight: .medium)
            searchBtn.contentTintColor = NSColor.white.withAlphaComponent(0.8)
            searchBtn.target = self
            searchBtn.action = #selector(onSearch)
            box.addSubview(searchBtn)
        }

        placePanel(content: box, near: anchor)
    }

    @objc private func onToggleLang() {
        let nextLang = (currentTargetLang == "en") ? "zh-CN" : "en"
        startInstantTranslate(at: currentAnchor, targetLang: nextLang)
    }

    @objc private func onCopyCard() {
        guard !translatedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translatedText, forType: .string)
        hintField?.stringValue = "✓ 已复制到剪贴板"
        hintField?.textColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    @objc private func onSearch() {
        panel.orderOut(nil)
        var comps = URLComponents(string: "https://www.google.com/search")!
        comps.queryItems = [URLQueryItem(name: "q", value: currentText)]
        if let url = comps.url { NSWorkspace.shared.open(url) }
    }

    private func placePanel(content: NSView, near point: NSPoint) {
        let size = content.frame.size
        var origin = NSPoint(x: round(point.x - size.width / 2), y: round(point.y + 14))
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
            if origin.y + size.height > vf.maxY - 8 {
                origin.y = round(point.y - size.height - 18)
            }
        }
        panel.contentView = content
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateStatusIcon()
    }
}

// MARK: - Entry Point
if CommandLine.arguments.contains("--test") {
    exit(Logic.runSelfTest() ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
