//
//  AtomicEditorCommandController.swift
//  Quick Notes
//
//  Created by Codex on 2026-06-19.
//

#if canImport(UIKit)
import UIKit
import WebKit

final class AtomicEditorCommandController: NSObject {
    var toolbarTintColor: UIColor = .secondaryLabel
    var isEditable: Bool = true
    var runJavaScript: ((String, ((Any?, Error?) -> Void)?) -> Void)?
    var hideKeyboard: (() -> Void)?
    var internalLinkBehavior: CodeMirrorAtomicInternalLinkBehavior = .default
    var imageBehavior: CodeMirrorAtomicImageBehavior = .default
    private weak var presentingView: UIView?

    func attach(to view: UIView) {
        presentingView = view
    }

    func makeToolbar() -> UIView {
        let toolbar = AtomicEditorKeyboardAccessoryView()
        let iconScale: CGFloat = 0.85
        let iconPointSize: CGFloat = 17 * iconScale
        let iconConfiguration = UIImage.SymbolConfiguration(
            font: UIFont.systemFont(ofSize: iconPointSize, weight: .semibold)
        )

        func icon(_ systemName: String) -> UIImage? {
            UIImage(systemName: systemName, withConfiguration: iconConfiguration)
        }

        let boldItem = toolbar.makeButton(
            image: UIImage(systemName: "bold"),
            accessibilityLabel: "Bold",
            target: self,
            action: #selector(insertBold)
        )

        let italicItem = toolbar.makeButton(
            image: UIImage(systemName: "italic"),
            accessibilityLabel: "Italic",
            target: self,
            action: #selector(insertItalic)
        )

        let codeItem = toolbar.makeButton(
            image: icon("chevron.left.chevron.right") ?? UIImage(systemName: "chevron.left.chevron.right"),
            accessibilityLabel: "Code",
            target: self,
            action: #selector(presentCodeOptions(_:))
        )

        let linkItem = toolbar.makeButton(
            image: icon("link") ?? UIImage(systemName: "link"),
            accessibilityLabel: "Link",
            target: self,
            action: #selector(insertMarkdownLink(_:))
        )

        let internalLinkItem = toolbar.makeButton(
            image: icon("text.page") ?? UIImage(systemName: "text.page"),
            accessibilityLabel: "Internal link",
            target: self,
            action: #selector(requestInternalLinkInsertion)
        )

        let imageItem = toolbar.makeButton(
            image: icon("photo") ?? UIImage(systemName: "photo"),
            accessibilityLabel: "Image",
            target: self,
            action: #selector(requestImageInsertion(_:))
        )

        let listItem = toolbar.makeButton(
            image: icon("list.bullet") ?? UIImage(systemName: "list.bullet"),
            accessibilityLabel: "List",
            target: self,
            action: #selector(presentListOptions(_:))
        )

        let headerItem = toolbar.makeTextButton(
            title: "H",
            accessibilityLabel: "Header",
            target: self,
            action: #selector(presentHeaderOptions(_:)),
            font: UIFont.systemFont(ofSize: 20, weight: .bold)
        )

        let hideKeyboardItem = toolbar.makeButton(
            image: icon("chevron.down") ?? UIImage(systemName: "chevron.down"),
            accessibilityLabel: "Hide keyboard",
            target: self,
            action: #selector(hideKeyboardTapped)
        )

        var buttons: [UIView] = [
            headerItem,
            boldItem,
            italicItem,
            listItem,
            linkItem,
            codeItem,
            hideKeyboardItem
        ]
        if showsInternalLinkButton {
            buttons.insert(internalLinkItem, at: 5)
        }
        if showsImageButton {
            buttons.insert(imageItem, at: min(buttons.count - 1, 6))
        }
        toolbar.setButtons(buttons)
        toolbar.applyTintColor(toolbarTintColor)
        return toolbar
    }

    private func evaluate(_ javascript: String, completion: ((Any?) -> Void)? = nil) {
        runJavaScript?(javascript) { result, error in
            guard error == nil else { return }
            completion?(result)
        }
    }

    private func quotedJavaScriptString(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2 else {
            return nil
        }
        return String(json.dropFirst().dropLast())
    }

    @objc private func hideKeyboardTapped() {
        hideKeyboard?()
    }

    @objc private func presentHeaderOptions(_ sender: UIButton) {
        presentToolbarOptions(
            [
                AtomicToolbarOption(title: "H1") { [weak self] in self?.insertHeading(level: 1) },
                AtomicToolbarOption(title: "H2") { [weak self] in self?.insertHeading(level: 2) },
                AtomicToolbarOption(title: "H3") { [weak self] in self?.insertHeading(level: 3) }
            ],
            from: sender
        )
    }

    @objc private func presentCodeOptions(_ sender: UIButton) {
        presentToolbarOptions(
            [
                AtomicToolbarOption(title: "inline") { [weak self] in self?.insertInlineCode() },
                AtomicToolbarOption(title: "block") { [weak self] in self?.insertCodeBlock() }
            ],
            from: sender
        )
    }

    @objc private func presentListOptions(_ sender: UIButton) {
        presentToolbarOptions(
            [
                AtomicToolbarOption(title: "bullets") { [weak self] in self?.insertBullet() },
                AtomicToolbarOption(title: "numbers") { [weak self] in self?.insertOrderedList() }
            ],
            from: sender
        )
    }

    @objc private func insertBold() {
        wrapSelection(prefix: "**", suffix: "**")
    }

    @objc private func insertItalic() {
        wrapSelection(prefix: "*", suffix: "*")
    }

    @objc private func insertInlineCode() {
        wrapSelection(prefix: "`", suffix: "`")
    }

    @objc private func insertCodeBlock() {
        wrapSelection(prefix: "```\n", suffix: "\n```")
    }

    @objc private func insertMarkdownLink(_ sender: UIButton) {
        evaluate("window.AtomicEditorHost?.selectedText?.() ?? ''") { [weak self] result in
            guard let self else { return }
            let selectedText = ((result as? String) ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let modal = AtomicLinkInsertModalViewController(
                initialDraft: AtomicLinkInsertionDraft(url: "", customText: selectedText),
                keyboardAccessoryView: (presentingView as? AtomicEditorWebView)?.inputAccessoryView
            ) { [weak self] draft in
                self?.applyLinkInsertion(draft)
            }
            modal.popoverPresentationController?.permittedArrowDirections = [.down, .up]
            modal.popoverPresentationController?.delegate = modal
            self.presentToolbarPopover(modal, from: sender) {
                modal.requestInitialFocusIfNeeded()
            }
        }
    }

    @objc private func insertBullet() {
        prefixSelectedLines(with: "- ")
    }

    @objc private func insertOrderedList() {
        evaluate("window.AtomicEditorHost?.prefixOrderedList?.(1);")
    }

    @objc private func requestInternalLinkInsertion() {
        switch internalLinkBehavior {
        case .hidden:
            return
        case .default:
            makeInsertionRequest { request in
                let selected = request.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
                request.insert(selected.isEmpty ? "[[]]" : "[[\(selected)]]")
            }
        case .custom(let handler):
            makeInsertionRequest(completion: handler)
        }
    }

    @objc private func requestImageInsertion(_ sender: UIButton) {
        switch imageBehavior {
        case .hidden:
            return
        case .default:
            makeInsertionRequest { [weak self] request in
                self?.presentDefaultImageInsertion(for: request, from: sender)
            }
        case .custom(let handler):
            makeInsertionRequest(completion: handler)
        }
    }

    private func insertHeading(level: Int) {
        let prefix = String(repeating: "#", count: min(max(level, 1), 6)) + " "
        replaceCurrentLinePrefix(with: prefix)
    }

    private func applyLinkInsertion(_ draft: AtomicLinkInsertionDraft) {
        let url = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty,
              let quotedURL = quotedJavaScriptString(url) else {
            return
        }

        let customText = draft.customText.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotedText = quotedJavaScriptString(customText) ?? "\"\""
        evaluate("window.AtomicEditorHost?.insertMarkdownLink?.(\(quotedURL), \(quotedText));")
    }

    private func wrapSelection(prefix: String, suffix: String) {
        guard let quotedPrefix = quotedJavaScriptString(prefix),
              let quotedSuffix = quotedJavaScriptString(suffix) else {
            return
        }
        evaluate("window.AtomicEditorHost?.wrapSelection?.(\(quotedPrefix), \(quotedSuffix));")
    }

    private func prefixSelectedLines(with prefix: String) {
        guard let quotedPrefix = quotedJavaScriptString(prefix) else { return }
        evaluate("window.AtomicEditorHost?.prefixSelectedLines?.(\(quotedPrefix));")
    }

    private func replaceCurrentLinePrefix(with prefix: String) {
        guard let quotedPrefix = quotedJavaScriptString(prefix) else { return }
        evaluate("window.AtomicEditorHost?.replaceCurrentLinePrefix?.(\(quotedPrefix));")
    }

    private func insertText(_ text: String) {
        guard let quotedText = quotedJavaScriptString(text) else { return }
        evaluate("window.AtomicEditorHost?.insertText?.(\(quotedText));")
    }

    private func makeInsertionRequest(completion: @escaping (CodeMirrorAtomicInsertionRequest) -> Void) {
        evaluate("window.AtomicEditorHost?.selectedText?.() ?? ''") { [weak self] result in
            guard let self else { return }
            let selectedText = (result as? String) ?? ""
            let request = CodeMirrorAtomicInsertionRequest(selectedText: selectedText) { [weak self] markdown in
                DispatchQueue.main.async {
                    self?.insertText(markdown)
                }
            }
            completion(request)
        }
    }

    private var showsInternalLinkButton: Bool {
        switch internalLinkBehavior {
        case .hidden:
            return false
        case .default, .custom:
            return true
        }
    }

    private var showsImageButton: Bool {
        switch imageBehavior {
        case .hidden:
            return false
        case .default, .custom:
            return true
        }
    }

    private func presentDefaultImageInsertion(for request: CodeMirrorAtomicInsertionRequest, from sourceView: UIView) {
        let selectedText = request.selectedText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let modal = AtomicImageInsertModalViewController(
            initialDraft: AtomicImageInsertionDraft(remoteURL: "", altText: selectedText),
            keyboardAccessoryView: (presentingView as? AtomicEditorWebView)?.inputAccessoryView
        ) { draft in
            let remoteURL = draft.remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remoteURL.isEmpty else { return }
            let altText = draft.altText.trimmingCharacters(in: .whitespacesAndNewlines)
            let escapedAltText = altText.replacingOccurrences(of: "]", with: #"\]"#)
            let escapedURL = remoteURL.replacingOccurrences(of: ")", with: #"\)"#)
            request.insert("![\(escapedAltText)](\(escapedURL))")
        }
        modal.popoverPresentationController?.permittedArrowDirections = [.down, .up]
        modal.popoverPresentationController?.delegate = modal
        presentToolbarPopover(modal, from: sourceView) {
            modal.requestInitialFocusIfNeeded()
        }
    }

    private func presentToolbarOptions(_ options: [AtomicToolbarOption], from sourceView: UIView) {
        let controller = AtomicToolbarOptionsPopoverController(
            options: options,
            tintColor: toolbarTintColor,
            backgroundColor: .secondarySystemBackground
        )
        controller.modalPresentationStyle = .popover
        controller.popoverPresentationController?.permittedArrowDirections = [.down, .up]
        controller.popoverPresentationController?.delegate = controller
        presentToolbarPopover(controller, from: sourceView)
    }

    private func presentToolbarPopover(_ controller: UIViewController,
                                       from sourceView: UIView,
                                       requestFocus: (() -> Void)? = nil) {
        guard let presenter = findPresentingViewController() else { return }
        let topPresenter = topPresentedViewController(from: presenter)
        guard !topPresenter.isBeingPresented, !topPresenter.isBeingDismissed else { return }
        if type(of: topPresenter) == type(of: controller), isToolbarTransientController(topPresenter) {
            topPresenter.dismiss(animated: true)
            return
        }
        if isToolbarTransientController(topPresenter) {
            let nextPresenter = topPresenter.presentingViewController ?? presenter
            topPresenter.dismiss(animated: false) { [weak self] in
                self?.presentToolbarPopover(controller, from: sourceView, presenter: nextPresenter, requestFocus: requestFocus)
            }
            return
        }
        presentToolbarPopover(controller, from: sourceView, presenter: topPresenter, requestFocus: requestFocus)
    }

    private func presentToolbarPopover(_ controller: UIViewController,
                                       from sourceView: UIView,
                                       presenter: UIViewController,
                                       requestFocus: (() -> Void)? = nil) {
        configurePopoverAnchor(for: controller.popoverPresentationController, sourceView: sourceView, presenter: presenter)
        presenter.present(controller, animated: true) {
            requestFocus?()
        }
    }

    private func findPresentingViewController() -> UIViewController? {
        var responder: UIResponder? = presentingView
        while let current = responder {
            if let viewController = current as? UIViewController,
               !isKeyboardPresentationController(viewController) {
                return viewController
            }
            responder = current.next
        }
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })?
            .rootViewController
    }

    private func topPresentedViewController(from presenter: UIViewController) -> UIViewController {
        var topPresenter = presenter
        while let presented = topPresenter.presentedViewController {
            topPresenter = presented
        }
        return topPresenter
    }

    private func isToolbarTransientController(_ viewController: UIViewController) -> Bool {
        if viewController is AtomicLinkInsertModalViewController
            || viewController is AtomicImageInsertModalViewController
            || viewController is AtomicToolbarOptionsPopoverController {
            return true
        }

        return viewController.modalPresentationStyle == .popover
            && viewController.presentingViewController === findPresentingViewController()
    }

    private func configurePopoverAnchor(for popover: UIPopoverPresentationController?,
                                        sourceView: UIView,
                                        presenter: UIViewController) {
        guard let popover else { return }
        popover.sourceView = presenter.view
        popover.sourceRect = sourceView.convert(sourceView.bounds, to: presenter.view)
    }

    private func isKeyboardPresentationController(_ viewController: UIViewController) -> Bool {
        let className = String(describing: type(of: viewController))
        return className.contains("UIInputWindowController")
            || className.contains("UICompatibilityInputViewController")
    }
}

final class AtomicEditorWebView: WKWebView {
    var accessoryView: UIView?

    override var inputAccessoryView: UIView? {
        accessoryView
    }
}

private struct AtomicToolbarOption {
    let title: String
    let action: () -> Void
}

private final class AtomicToolbarOptionsPopoverController: UIViewController, UIPopoverPresentationControllerDelegate {
    private let topInset: CGFloat = 8
    private let bottomInset: CGFloat = 18
    private let rowHeight: CGFloat = 40
    private let separatorHeight: CGFloat = 1 / UIScreen.main.scale
    private let options: [AtomicToolbarOption]
    private let tintColor: UIColor
    private let fillColor: UIColor

    init(options: [AtomicToolbarOption], tintColor: UIColor, backgroundColor: UIColor) {
        self.options = options
        self.tintColor = tintColor
        self.fillColor = backgroundColor
        super.init(nibName: nil, bundle: nil)
        modalPresentationCapturesStatusBarAppearance = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = fillColor
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: topInset),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -bottomInset)
        ])

        for (index, option) in options.enumerated() {
            let row = AtomicToolbarOptionRowView(
                title: option.title,
                tintColor: tintColor,
                rowHeight: rowHeight
            )
            row.addAction(UIAction { [weak self] _ in
                self?.dismiss(animated: true) {
                    option.action()
                }
            }, for: .touchUpInside)
            stackView.addArrangedSubview(row)

            if index < options.count - 1 {
                let separator = UIView()
                separator.backgroundColor = UIColor.separator.withAlphaComponent(0.6)
                separator.heightAnchor.constraint(equalToConstant: separatorHeight).isActive = true
                stackView.addArrangedSubview(separator)
            }
        }

        let separatorCount = max(0, options.count - 1)
        preferredContentSize = CGSize(
            width: 132,
            height: CGFloat(options.count) * rowHeight
                + (CGFloat(separatorCount) * separatorHeight)
                + topInset
                + bottomInset
        )
    }

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }
}

private final class AtomicToolbarOptionRowView: UIControl {
    private let titleLabel = UILabel()

    init(title: String, tintColor: UIColor, rowHeight: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.textColor = tintColor
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private enum AtomicLinkInsertionMode: Equatable {
    case plainURL
    case markdown(label: String)
}

private struct AtomicLinkInsertionDraft: Equatable {
    var url: String
    var customText: String

    var mode: AtomicLinkInsertionMode {
        let trimmedLabel = customText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLabel.isEmpty {
            return .plainURL
        }
        return .markdown(label: trimmedLabel)
    }
}

private struct AtomicImageInsertionDraft: Equatable {
    var remoteURL: String
    var altText: String
}

private final class AtomicLinkInsertModalViewController: UIViewController, UIPopoverPresentationControllerDelegate {
    private let horizontalInset: CGFloat = 12
    private let verticalInset: CGFloat = 0
    private let rowHeight: CGFloat = 40
    private let initialDraft: AtomicLinkInsertionDraft
    private let keyboardAccessoryView: UIView?
    private let onInsert: (AtomicLinkInsertionDraft) -> Void
    private var hasRequestedInitialFocus = false

    private let urlTextField = UITextField()
    private let labelTextField = UITextField()
    private let insertButton = UIButton(type: .system)
    private let contentStack = UIStackView()

    init(initialDraft: AtomicLinkInsertionDraft,
         keyboardAccessoryView: UIView? = nil,
         onInsert: @escaping (AtomicLinkInsertionDraft) -> Void) {
        self.initialDraft = initialDraft
        self.keyboardAccessoryView = keyboardAccessoryView
        self.onInsert = onInsert
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .popover
        modalPresentationCapturesStatusBarAppearance = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true

        configureLayout()
        configureFields()
        apply(initialDraft)
        updateInsertButtonEnabled()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let targetWidth: CGFloat = 320
        let targetSize = CGSize(width: targetWidth - (horizontalInset * 2),
                                height: UIView.layoutFittingCompressedSize.height)
        let fittedContent = contentStack.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        preferredContentSize = CGSize(width: targetWidth, height: ceil(fittedContent.height + (verticalInset * 2)))
    }

    func requestInitialFocusIfNeeded() {
        guard hasRequestedInitialFocus == false else { return }
        hasRequestedInitialFocus = true
        DispatchQueue.main.async { [weak self] in
            self?.urlTextField.becomeFirstResponder()
        }
    }

    private func configureLayout() {
        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: verticalInset),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: horizontalInset),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -horizontalInset),
            contentStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -verticalInset)
        ])

        urlTextField.borderStyle = .roundedRect
        urlTextField.keyboardType = .URL
        urlTextField.textContentType = .URL
        urlTextField.autocapitalizationType = .none
        urlTextField.autocorrectionType = .no
        urlTextField.placeholder = "URL"
        urlTextField.addTarget(self, action: #selector(textFieldEditingChanged), for: .editingChanged)
        urlTextField.returnKeyType = .next
        urlTextField.delegate = self
        urlTextField.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        contentStack.addArrangedSubview(urlTextField)

        labelTextField.borderStyle = .roundedRect
        labelTextField.autocapitalizationType = .sentences
        labelTextField.autocorrectionType = .default
        labelTextField.placeholder = "Custom text (optional)"
        labelTextField.addTarget(self, action: #selector(textFieldEditingChanged), for: .editingChanged)
        labelTextField.returnKeyType = .done
        labelTextField.delegate = self
        labelTextField.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        contentStack.addArrangedSubview(labelTextField)

        let buttonsRow = UIStackView()
        buttonsRow.axis = .horizontal
        buttonsRow.alignment = .center
        buttonsRow.setContentHuggingPriority(.required, for: .vertical)
        buttonsRow.setContentCompressionResistancePriority(.required, for: .vertical)
        contentStack.addArrangedSubview(buttonsRow)
        buttonsRow.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buttonsRow.addArrangedSubview(spacer)

        insertButton.setTitle("Insert", for: .normal)
        insertButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
        insertButton.configuration = buttonConfiguration
        insertButton.addTarget(self, action: #selector(insertTapped), for: .touchUpInside)
        insertButton.setContentHuggingPriority(.required, for: .horizontal)
        insertButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        buttonsRow.addArrangedSubview(insertButton)

        preferredContentSize = CGSize(width: 320, height: rowHeight * 3)
    }

    private func configureFields() {
        urlTextField.inputAccessoryView = keyboardAccessoryView
        labelTextField.inputAccessoryView = keyboardAccessoryView
        urlTextField.clearButtonMode = .whileEditing
        labelTextField.clearButtonMode = .whileEditing
    }

    private func apply(_ draft: AtomicLinkInsertionDraft) {
        urlTextField.text = draft.url
        labelTextField.text = draft.customText
    }

    private func currentDraft() -> AtomicLinkInsertionDraft {
        AtomicLinkInsertionDraft(
            url: (urlTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            customText: (labelTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func updateInsertButtonEnabled() {
        let url = (urlTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        insertButton.isEnabled = !url.isEmpty
    }

    @objc private func textFieldEditingChanged() {
        updateInsertButtonEnabled()
    }

    @objc private func insertTapped() {
        let draft = currentDraft()
        guard !draft.url.isEmpty else { return }
        dismiss(animated: true) { [onInsert] in
            onInsert(draft)
        }
    }

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }
}

extension AtomicLinkInsertModalViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === urlTextField {
            labelTextField.becomeFirstResponder()
            return false
        }

        if textField === labelTextField, insertButton.isEnabled {
            insertTapped()
            return false
        }

        return true
    }
}

private final class AtomicImageInsertModalViewController: UIViewController, UIPopoverPresentationControllerDelegate {
    private let horizontalInset: CGFloat = 12
    private let verticalInset: CGFloat = 0
    private let rowHeight: CGFloat = 40
    private let initialDraft: AtomicImageInsertionDraft
    private let keyboardAccessoryView: UIView?
    private let onInsert: (AtomicImageInsertionDraft) -> Void
    private var hasRequestedInitialFocus = false

    private let urlTextField = UITextField()
    private let altTextField = UITextField()
    private let insertButton = UIButton(type: .system)
    private let contentStack = UIStackView()

    init(initialDraft: AtomicImageInsertionDraft,
         keyboardAccessoryView: UIView? = nil,
         onInsert: @escaping (AtomicImageInsertionDraft) -> Void) {
        self.initialDraft = initialDraft
        self.keyboardAccessoryView = keyboardAccessoryView
        self.onInsert = onInsert
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .popover
        modalPresentationCapturesStatusBarAppearance = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true

        configureLayout()
        configureFields()
        apply(initialDraft)
        updateInsertButtonEnabled()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let targetWidth: CGFloat = 320
        let targetSize = CGSize(width: targetWidth - (horizontalInset * 2),
                                height: UIView.layoutFittingCompressedSize.height)
        let fittedContent = contentStack.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        preferredContentSize = CGSize(width: targetWidth, height: ceil(fittedContent.height + (verticalInset * 2)))
    }

    func requestInitialFocusIfNeeded() {
        guard hasRequestedInitialFocus == false else { return }
        hasRequestedInitialFocus = true
        DispatchQueue.main.async { [weak self] in
            self?.urlTextField.becomeFirstResponder()
        }
    }

    private func configureLayout() {
        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: verticalInset),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: horizontalInset),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -horizontalInset),
            contentStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -verticalInset)
        ])

        urlTextField.borderStyle = .roundedRect
        urlTextField.keyboardType = .URL
        urlTextField.textContentType = .URL
        urlTextField.autocapitalizationType = .none
        urlTextField.autocorrectionType = .no
        urlTextField.placeholder = "Image URL"
        urlTextField.addTarget(self, action: #selector(textFieldEditingChanged), for: .editingChanged)
        urlTextField.returnKeyType = .next
        urlTextField.delegate = self
        urlTextField.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        contentStack.addArrangedSubview(urlTextField)

        altTextField.borderStyle = .roundedRect
        altTextField.autocapitalizationType = .sentences
        altTextField.autocorrectionType = .default
        altTextField.placeholder = "Alt text (optional)"
        altTextField.addTarget(self, action: #selector(textFieldEditingChanged), for: .editingChanged)
        altTextField.returnKeyType = .done
        altTextField.delegate = self
        altTextField.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        contentStack.addArrangedSubview(altTextField)

        let buttonsRow = UIStackView()
        buttonsRow.axis = .horizontal
        buttonsRow.alignment = .center
        buttonsRow.setContentHuggingPriority(.required, for: .vertical)
        buttonsRow.setContentCompressionResistancePriority(.required, for: .vertical)
        contentStack.addArrangedSubview(buttonsRow)
        buttonsRow.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buttonsRow.addArrangedSubview(spacer)

        insertButton.setTitle("Insert", for: .normal)
        insertButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
        insertButton.configuration = buttonConfiguration
        insertButton.addTarget(self, action: #selector(insertTapped), for: .touchUpInside)
        insertButton.setContentHuggingPriority(.required, for: .horizontal)
        insertButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        buttonsRow.addArrangedSubview(insertButton)

        preferredContentSize = CGSize(width: 320, height: rowHeight * 3)
    }

    private func configureFields() {
        urlTextField.inputAccessoryView = keyboardAccessoryView
        altTextField.inputAccessoryView = keyboardAccessoryView
        urlTextField.clearButtonMode = .whileEditing
        altTextField.clearButtonMode = .whileEditing
    }

    private func apply(_ draft: AtomicImageInsertionDraft) {
        urlTextField.text = draft.remoteURL
        altTextField.text = draft.altText
    }

    private func currentDraft() -> AtomicImageInsertionDraft {
        AtomicImageInsertionDraft(
            remoteURL: (urlTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            altText: (altTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func updateInsertButtonEnabled() {
        let remoteURL = (urlTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        insertButton.isEnabled = !remoteURL.isEmpty
    }

    @objc private func textFieldEditingChanged() {
        updateInsertButtonEnabled()
    }

    @objc private func insertTapped() {
        let draft = currentDraft()
        guard !draft.remoteURL.isEmpty else { return }
        dismiss(animated: true) { [onInsert] in
            onInsert(draft)
        }
    }

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }
}

extension AtomicImageInsertModalViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === urlTextField {
            altTextField.becomeFirstResponder()
            return false
        }

        if textField === altTextField, insertButton.isEnabled {
            insertTapped()
            return false
        }

        return true
    }
}

final class AtomicEditorKeyboardAccessoryView: UIView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let stackView = UIStackView()
    private var buttons: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = .clear
        configureBlur()
        configureStack()
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func makeButton(image: UIImage?,
                    accessibilityLabel: String,
                    target: Any?,
                    action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = image
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        button.configuration = configuration
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(target, action: action, for: .touchUpInside)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        return button
    }

    func makeTextButton(title: String,
                        accessibilityLabel: String,
                        target: Any?,
                        action: Selector,
                        font: UIFont) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        button.configuration = configuration
        button.configurationUpdateHandler = { updatedButton in
            var updatedConfiguration = updatedButton.configuration ?? .plain()
            updatedConfiguration.attributedTitle = AttributedString(
                title,
                attributes: AttributeContainer([
                    .font: font
                ])
            )
            updatedButton.configuration = updatedConfiguration
        }
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(target, action: action, for: .touchUpInside)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        return button
    }

    func setButtons(_ buttons: [UIView]) {
        self.buttons.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        self.buttons = buttons
        buttons.forEach { stackView.addArrangedSubview($0) }
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stackView.addArrangedSubview(spacer)
    }

    func applyTintColor(_ color: UIColor) {
        buttons.compactMap { $0 as? UIButton }.forEach { button in
            button.tintColor = color
            button.setTitleColor(color, for: .normal)
        }
    }

    private func configureBlur() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func configureStack() {
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
    }
}

#endif
