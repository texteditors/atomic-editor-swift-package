//
//  CodeMirrorAtomicTextEditor.swift
//  Quick Notes
//
//  Created by Codex on 2026-06-11.
//

#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
import WebKit

public struct CodeMirrorAtomicTextEditor: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var text: String
    var accentColor: UIColor
    var documentIdentity: String? = nil
    var isFocused: Binding<Bool>? = nil
    var isEditable: Bool = true
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var fontFamilyCSS: String? = nil
    var codeFont: UIFont = .monospacedSystemFont(ofSize: 16, weight: .regular)
    var codeFontFamilyCSS: String? = nil
    var headingFontSizes: [Int: CGFloat] = [:]
    var lineHeightMultiple: Double = 1.45
    var lineWidthColumns: Double = 70
    var colorSchemeOverride: ColorScheme? = nil
    var textColor: UIColor = .label
    var codeBackgroundBaseColor: UIColor = .systemBackground
    var onTextChange: ((String) -> Void)? = nil
    var internalLinkBehavior: CodeMirrorAtomicInternalLinkBehavior = .default
    var imageBehavior: CodeMirrorAtomicImageBehavior = .default

    public init(text: Binding<String>,
                accentColor: UIColor,
                documentIdentity: String? = nil,
                isFocused: Binding<Bool>? = nil,
                isEditable: Bool = true,
                font: UIFont = .preferredFont(forTextStyle: .body),
                fontFamilyCSS: String? = nil,
                codeFont: UIFont = .monospacedSystemFont(ofSize: 16, weight: .regular),
                codeFontFamilyCSS: String? = nil,
                headingFontSizes: [Int: CGFloat] = [:],
                lineHeightMultiple: Double = 1.45,
                lineWidthColumns: Double = 70,
                colorSchemeOverride: ColorScheme? = nil,
                textColor: UIColor = .label,
                codeBackgroundBaseColor: UIColor = .systemBackground,
                onTextChange: ((String) -> Void)? = nil,
                internalLinkBehavior: CodeMirrorAtomicInternalLinkBehavior = .default,
                imageBehavior: CodeMirrorAtomicImageBehavior = .default) {
        self._text = text
        self.accentColor = accentColor
        self.documentIdentity = documentIdentity
        self.isFocused = isFocused
        self.isEditable = isEditable
        self.font = font
        self.fontFamilyCSS = fontFamilyCSS
        self.codeFont = codeFont
        self.codeFontFamilyCSS = codeFontFamilyCSS
        self.headingFontSizes = headingFontSizes
        self.lineHeightMultiple = lineHeightMultiple
        self.lineWidthColumns = lineWidthColumns
        self.colorSchemeOverride = colorSchemeOverride
        self.textColor = textColor
        self.codeBackgroundBaseColor = codeBackgroundBaseColor
        self.onTextChange = onTextChange
        self.internalLinkBehavior = internalLinkBehavior
        self.imageBehavior = imageBehavior
    }

    private let bridgeName = "codeMirrorAtomicBridge"

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private var resolvedColorScheme: ColorScheme {
        colorSchemeOverride ?? colorScheme
    }

    public func makeUIView(context: Context) -> WKWebView {
        print("[CodeMirrorAtomic] makeUIView textChars=\(text.count) editable=\(isEditable)")
        let webView = context.coordinator.makeOrReuseWebView()
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.delaysContentTouches = false

        context.coordinator.webView = webView
        context.coordinator.prepareEditorForDisplay()
        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        print("[CodeMirrorAtomic] updateUIView bounds=\(Int(webView.bounds.width))x\(Int(webView.bounds.height)) textChars=\(text.count)")
        if webView.url == nil && webView.isLoading == false {
            context.coordinator.loadEditor()
        } else if webView.url != nil && webView.isLoading == false && !context.coordinator.isEditorReady {
            context.coordinator.recoverLoadedEditorIfPossible(on: webView)
        }
        context.coordinator.configureAccessory(for: webView)
        context.coordinator.updateToolbarAppearanceIfNeeded()
        context.coordinator.pushConfigurationToEditor(force: false)
    }

    public static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        coordinator.storeForReuse(webView)
    }

    public static func prewarm() {
        prewarmEditor()
    }

    public static func prewarmEditor() {
        Coordinator.prewarm()
    }

    private static func makeWebViewConfiguration(bridgeName: String,
                                                 messageHandler: WKScriptMessageHandler? = nil) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        Coordinator.configureProcessPool(for: configuration)
        if let messageHandler {
            configuration.userContentController.add(messageHandler, name: bridgeName)
        }
        return configuration
    }

    public final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: CodeMirrorAtomicTextEditor
        weak var webView: WKWebView?
        let commandController: AtomicEditorCommandController

        var isEditorReady = false
        private var didFinishLoadingEditor = false
        private var pendingFocusRequest = false
        private var didAutoFocus = false
        private var lastRenderedText = ""
        private var lastAppliedConfiguration = ""
        private var lastToolbarTintSignature = ""
        private var lastAccessorySignature = ""
        private weak var accessoryHostView: WKWebView?

#if !targetEnvironment(macCatalyst)
        private static let sharedProcessPool = WKProcessPool()
#endif
        private static var prewarmWebView: WKWebView?
        private static var reusableWebView: WKWebView?

        init(parent: CodeMirrorAtomicTextEditor) {
            self.parent = parent
            self.commandController = AtomicEditorCommandController()
            super.init()
            commandController.isEditable = parent.isEditable
            commandController.toolbarTintColor = .secondaryLabel
        }

        static func prewarm() {
            guard reusableWebView == nil,
                  prewarmWebView == nil,
                  let htmlURL = editorHTMLURL() else {
                return
            }

            let configuration = WKWebViewConfiguration()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            configureProcessPool(for: configuration)
            let webView = AtomicEditorWebView(frame: .zero, configuration: configuration)
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
            prewarmWebView = webView
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        static func configureProcessPool(for configuration: WKWebViewConfiguration) {
#if !targetEnvironment(macCatalyst)
            configuration.processPool = sharedProcessPool
#endif
        }

        func makeOrReuseWebView() -> WKWebView {
            if let webView = Self.reusableWebView {
                Self.reusableWebView = nil
                attachBridge(to: webView)
                configureAccessory(for: webView)
                log("reusing cached webview")
                return webView
            }

            if let webView = Self.prewarmWebView {
                Self.prewarmWebView = nil
                attachBridge(to: webView)
                configureAccessory(for: webView)
                log("adopting prewarmed webview")
                return webView
            }

            let configuration = CodeMirrorAtomicTextEditor.makeWebViewConfiguration(bridgeName: parent.bridgeName,
                                                                                    messageHandler: self)
            log("creating fresh webview")
            let webView = AtomicEditorWebView(frame: .zero, configuration: configuration)
            configureAccessory(for: webView)
            return webView
        }

        func prepareEditorForDisplay() {
            didAutoFocus = false
            pendingFocusRequest = false
            guard let webView else { return }
            if webView.isLoading {
                log("webview still loading on attach; reloading under live delegate")
                webView.stopLoading()
                loadEditor()
                return
            }
            if webView.url == nil {
                loadEditor()
                return
            }
            recoverLoadedEditorIfPossible(on: webView)
        }

        func loadEditor() {
            guard let webView,
                  let htmlURL = Self.editorHTMLURL() else {
                log("editor HTML resource was not found")
                return
            }

            if webView.isLoading {
                webView.stopLoading()
            }
            didFinishLoadingEditor = false
            isEditorReady = false
            didAutoFocus = false
            pendingFocusRequest = false
            log("loading editor HTML from \(htmlURL.path)")
            let readAccessURL = htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: readAccessURL)
        }

        func storeForReuse(_ webView: WKWebView) {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: parent.bridgeName)
            webView.stopLoading()
            webView.removeFromSuperview()
            if Self.reusableWebView == nil {
                Self.reusableWebView = webView
                log("stored webview for reuse")
            } else {
                log("discarded extra reusable webview")
            }
        }

        func configureAccessory(for webView: WKWebView) {
            commandController.attach(to: webView)
            commandController.isEditable = parent.isEditable
            commandController.internalLinkBehavior = parent.internalLinkBehavior
            commandController.imageBehavior = parent.imageBehavior
            commandController.runJavaScript = { [weak webView] javascript, completion in
                webView?.evaluateJavaScript(javascript, completionHandler: completion)
            }
            commandController.hideKeyboard = { [weak self] in
                self?.webView?.evaluateJavaScript("window.AtomicEditorHost?.blur?.();") { _, _ in }
                self?.webView?.resignFirstResponder()
                self?.parent.isFocused?.wrappedValue = false
            }

            guard let accessoryWebView = webView as? AtomicEditorWebView else { return }
            let accessorySignature = "\(commandVisibilitySignature(for: parent.internalLinkBehavior))|\(commandVisibilitySignature(for: parent.imageBehavior))"
            if accessoryHostView !== webView
                || accessoryWebView.accessoryView == nil
                || lastAccessorySignature != accessorySignature {
                accessoryWebView.accessoryView = commandController.makeToolbar()
                accessoryHostView = webView
                lastAccessorySignature = accessorySignature
                accessoryWebView.reloadInputViews()
            }
        }

        private func commandVisibilitySignature(for behavior: CodeMirrorAtomicInternalLinkBehavior) -> String {
            switch behavior {
            case .hidden:
                return "hidden"
            case .default:
                return "default"
            case .custom:
                return "custom"
            }
        }

        private func commandVisibilitySignature(for behavior: CodeMirrorAtomicImageBehavior) -> String {
            switch behavior {
            case .hidden:
                return "hidden"
            case .default:
                return "default"
            case .custom:
                return "custom"
            }
        }

        func updateToolbarAppearanceIfNeeded() {
            guard let accessoryWebView = webView as? AtomicEditorWebView,
                  let toolbar = accessoryWebView.accessoryView as? AtomicEditorKeyboardAccessoryView else {
                return
            }

            let tintSignature = "\(parent.isEditable)|\(commandVisibilitySignature(for: parent.internalLinkBehavior))|\(commandVisibilitySignature(for: parent.imageBehavior))"
            guard tintSignature != lastToolbarTintSignature else { return }
            lastToolbarTintSignature = tintSignature
            commandController.isEditable = parent.isEditable
            commandController.toolbarTintColor = parent.isEditable ? .secondaryLabel : .tertiaryLabel
            toolbar.applyTintColor(commandController.toolbarTintColor)
            accessoryWebView.reloadInputViews()
        }

        private static func editorHTMLURL() -> URL? {
            let candidateURLs: [URL?] = [
                Bundle.module.url(forResource: "index", withExtension: "html"),
                Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "CodeMirrorAtomic"),
                Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Resources/CodeMirrorAtomic"),
                Bundle.module.resourceURL?.appendingPathComponent("index.html"),
                Bundle.module.resourceURL?.appendingPathComponent("CodeMirrorAtomic/index.html"),
                Bundle.module.resourceURL?.appendingPathComponent("Resources/CodeMirrorAtomic/index.html")
            ]

            let fileManager = FileManager.default
            for candidate in candidateURLs {
                guard let candidate else { continue }
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }

            return nil
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishLoadingEditor = true
            log("webview didFinish url=\(webView.url?.absoluteString ?? "nil")")
            pushConfigurationToEditor(force: true)
        }

        public func userContentController(_ userContentController: WKUserContentController,
                                          didReceive message: WKScriptMessage) {
            guard message.name == parent.bridgeName,
                  let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String else {
                return
            }

            switch type {
            case "ready":
                log("ready")
                isEditorReady = true
                pushConfigurationToEditor(force: true)
                if pendingFocusRequest {
                    pendingFocusRequest = false
                    focusEditor()
                }
            case "configured":
                log("configured \(diagnosticSummary(from: payload))")
            case "error":
                log("javascript error \(diagnosticSummary(from: payload))")
            case "focusChanged":
                guard let focused = payload["isFocused"] as? Bool else { return }
                DispatchQueue.main.async {
                    self.parent.isFocused?.wrappedValue = focused
                }
            case "textChange":
                guard let updatedText = payload["text"] as? String else { return }
                applyEditorText(updatedText)
            case "writeClipboard":
                guard let text = payload["text"] as? String else { return }
                writeClipboard(text)
            case "readClipboard":
                pasteClipboardIntoEditor()
            default:
                log("message \(type) \(diagnosticSummary(from: payload))")
                break
            }
        }

        private func writeClipboard(_ text: String) {
            UIPasteboard.general.string = text
            log("clipboard updated chars=\(text.count)")
        }

        private func pasteClipboardIntoEditor() {
            guard let webView else { return }
            let text = UIPasteboard.general.string ?? ""
            guard let payload = jsonStringLiteral(text) else {
                log("clipboard read failed: could not encode payload")
                return
            }
            let javaScript = "window.AtomicEditorHost?.pasteFromHostClipboard(\(payload));"
            webView.evaluateJavaScript(javaScript) { _, error in
                if let error {
                    self.log("paste evaluation failed: \(error.localizedDescription)")
                    return
                }
                self.log("clipboard pasted chars=\(text.count)")
            }
        }

        private func jsonStringLiteral(_ text: String) -> String? {
            guard let data = try? JSONSerialization.data(withJSONObject: [text], options: []),
                  let json = String(data: data, encoding: .utf8),
                  json.count >= 2 else {
                return nil
            }
            return String(json.dropFirst().dropLast())
        }

        private func applyEditorText(_ updatedText: String) {
            lastRenderedText = updatedText
            parent.onTextChange?(updatedText)
            guard updatedText != parent.text else {
                return
            }

            let applyBinding = {
                self.parent.text = updatedText
            }

            if Thread.isMainThread {
                applyBinding()
            } else {
                DispatchQueue.main.async(execute: applyBinding)
            }
        }

        public func pushConfigurationToEditor(force: Bool) {
            guard isEditorReady,
                  didFinishLoadingEditor,
                  let webView,
                  let configuration = editorConfigurationJSON() else {
                if !isEditorReady {
                    log("configure skipped: editor not ready")
                } else if !didFinishLoadingEditor {
                    log("configure deferred: editor navigation not finished")
                }
                return
            }

            if !force && configuration == lastAppliedConfiguration {
                syncFocusIfNeeded(on: webView)
                return
            }

            lastAppliedConfiguration = configuration
            lastRenderedText = parent.text

            let javaScript = """
            if (window.AtomicEditorHost) {
              window.AtomicEditorHost.configure(\(configuration));
            } else {
              throw new Error("AtomicEditorHost is not available");
            }
            """
            webView.evaluateJavaScript(javaScript) { _, error in
                if let error {
                    self.log("configure evaluation failed: \(error.localizedDescription)")
                    return
                }

                self.autofocusIfNeeded()
            }
            syncFocusIfNeeded(on: webView)
        }

        private func autofocusIfNeeded() {
            guard parent.isFocused == nil,
                  parent.isEditable,
                  !didAutoFocus else {
                return
            }

            didAutoFocus = true
            DispatchQueue.main.async {
                self.focusEditor()
            }
        }

        private func syncFocusIfNeeded(on webView: WKWebView) {
            guard let isFocused = parent.isFocused?.wrappedValue else { return }
            if isFocused {
                guard isEditorReady else {
                    pendingFocusRequest = true
                    return
                }
                webView.becomeFirstResponder()
                webView.evaluateJavaScript("window.AtomicEditorHost?.focus();") { _, error in
                    if let error {
                        self.log("focus evaluation failed: \(error.localizedDescription)")
                    }
                }
            } else {
                webView.evaluateJavaScript("window.AtomicEditorHost?.blur();") { _, error in
                    if let error {
                        self.log("blur evaluation failed: \(error.localizedDescription)")
                    }
                }
                webView.resignFirstResponder()
            }
        }

        private func focusEditor() {
            guard let webView else { return }
            guard isEditorReady else {
                pendingFocusRequest = true
                if webView.url == nil && webView.isLoading == false {
                    loadEditor()
                }
                return
            }
            webView.becomeFirstResponder()
            webView.evaluateJavaScript("window.AtomicEditorHost?.focus();") { _, error in
                if let error {
                    self.log("tap focus evaluation failed: \(error.localizedDescription)")
                }
            }
        }

        public func webView(_ webView: WKWebView,
                            didFail navigation: WKNavigation!,
                            withError error: Error) {
            log("navigation failed: \(error.localizedDescription)")
        }

        public func webView(_ webView: WKWebView,
                            didFailProvisionalNavigation navigation: WKNavigation!,
                            withError error: Error) {
            log("provisional navigation failed: \(error.localizedDescription)")
        }

        public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            log("web content process terminated")
            isEditorReady = false
            didFinishLoadingEditor = false
            didAutoFocus = false
            pendingFocusRequest = false
            webView.reload()
        }

        func recoverLoadedEditorIfPossible(on webView: WKWebView) {
            guard webView.isLoading == false, webView.url != nil else {
                return
            }

            didFinishLoadingEditor = true
            let javaScript = "Boolean(window.AtomicEditorHost)"
            webView.evaluateJavaScript(javaScript) { result, error in
                if let error {
                    self.log("ready probe failed: \(error.localizedDescription)")
                    self.loadEditor()
                    return
                }

                guard let isHostReady = result as? Bool, isHostReady else {
                    self.log("ready probe missed host; reloading editor")
                    self.loadEditor()
                    return
                }

                self.log("recovered loaded editor without reload")
                self.isEditorReady = true
                self.pushConfigurationToEditor(force: true)
            }
        }

        private func editorConfigurationJSON() -> String? {
            let currentColorScheme = parent.resolvedColorScheme
            let traits = UITraitCollection(userInterfaceStyle: currentColorScheme == .dark ? .dark : .light)
            let accentColor = parent.accentColor.resolvedColor(with: traits)

            #if targetEnvironment(macCatalyst)
            let measure = "\(Int(min(90, max(parent.lineWidthColumns, 84)).rounded()))ch"
            #else
            let measure = "\(Int(parent.lineWidthColumns.rounded()))ch"
            #endif

            var payload: [String: Any] = [
                "isEditable": parent.isEditable,
                "documentIdentity": parent.documentIdentity ?? "",
                "theme": currentColorScheme == .light ? "light" : "dark",
                "fontFamily": parent.fontFamilyCSS ?? cssFontFamily(for: parent.font),
                "codeFontFamily": parent.codeFontFamilyCSS ?? cssFontFamily(for: parent.codeFont),
                "fontSizePx": parent.font.pointSize,
                "headingFontSizesPx": [
                    "1": parent.headingFontSizes[1] ?? parent.font.pointSize * 2.0,
                    "2": parent.headingFontSizes[2] ?? parent.font.pointSize * 1.6,
                    "3": parent.headingFontSizes[3] ?? parent.font.pointSize * 1.4,
                    "4": parent.headingFontSizes[4] ?? parent.font.pointSize * 1.2
                ],
                "lineHeight": parent.lineHeightMultiple,
                "measure": measure,
                "colors": [
                    "background": resolvedHex(.clear, traits: traits),
                    "panel": resolvedHex(.secondarySystemBackground, traits: traits),
                    "surface": resolvedHex(.tertiarySystemBackground, traits: traits),
                    "border": resolvedHex(.separator, traits: traits),
                    "foreground": resolvedHex(parent.textColor, traits: traits),
                    "muted": resolvedHex(.secondaryLabel, traits: traits),
                    "faint": resolvedHex(.tertiaryLabel, traits: traits),
                    "accent": accentColor.cssHexString,
                    "accentBright": accentColor.withAlphaComponent(0.85).cssHexString,
                    "link": accentColor.cssHexString,
                    "linkHover": accentColor.cssHexString,
                    "codeBackground": resolvedHex(parent.codeBackgroundBaseColor, traits: traits),
                    "selection": accentColor.withAlphaComponent(0.28).cssHexString,
                    "search": accentColor.withAlphaComponent(0.24).cssHexString,
                    "searchActive": accentColor.withAlphaComponent(0.45).cssHexString
                ]
            ]

            payload["text"] = parent.text

            guard JSONSerialization.isValidJSONObject(payload),
                  let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        }

        private func cssFontFamily(for font: UIFont) -> String {
            if font.familyName.localizedCaseInsensitiveContains("System") {
                return "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", system-ui, sans-serif"
            }
            let familyName = font.familyName.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(familyName)\""
        }

        private func resolvedHex(_ color: UIColor, traits: UITraitCollection) -> String {
            color.resolvedColor(with: traits).cssHexString
        }

        private func diagnosticSummary(from payload: [String: Any]) -> String {
            payload
                .filter { $0.key != "type" }
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: " ")
        }

        private func log(_ message: String) {
            print("[CodeMirrorAtomic] \(message)")
        }

        private func attachBridge(to webView: WKWebView) {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: parent.bridgeName)
            webView.configuration.userContentController.add(self, name: parent.bridgeName)
        }
    }
}

private extension UIColor {
    var cssHexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#000000"
        }

        let redValue = Int(round(red * 255))
        let greenValue = Int(round(green * 255))
        let blueValue = Int(round(blue * 255))
        let alphaValue = Int(round(alpha * 255))

        if alphaValue < 255 {
            return String(format: "#%02X%02X%02X%02X", redValue, greenValue, blueValue, alphaValue)
        }

        return String(format: "#%02X%02X%02X", redValue, greenValue, blueValue)
    }
}
#endif
