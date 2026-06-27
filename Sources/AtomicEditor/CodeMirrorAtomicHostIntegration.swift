//
//  CodeMirrorAtomicHostIntegration.swift
//  Quick Notes
//
//  Created by Codex on 2026-06-22.
//

import Foundation

public struct CodeMirrorAtomicInsertionRequest {
    public let selectedText: String
    private let inserter: (String) -> Void

    public init(selectedText: String, inserter: @escaping (String) -> Void) {
        self.selectedText = selectedText
        self.inserter = inserter
    }

    public func insert(_ markdown: String) {
        inserter(markdown)
    }
}

public enum CodeMirrorAtomicInternalLinkBehavior {
    case hidden
    case `default`
    case custom((CodeMirrorAtomicInsertionRequest) -> Void)
}

public enum CodeMirrorAtomicImageBehavior {
    case hidden
    case `default`
    case custom((CodeMirrorAtomicInsertionRequest) -> Void)
}
