# Atomic Editor Swift Package

Shared Swift wrapper and bundled web assets for the Atomic CodeMirror editor.

This package contains:

- the `CodeMirrorAtomicTextEditor` SwiftUI wrapper
- the keyboard accessory toolbar and host bridge
- the bundled Atomic editor runtime under `Resources/CodeMirrorAtomic`
- shared insertion request and behavior types for internal links and images

The package is intended to be consumed by both:

- `TextEditLabApp`
- `ZapNotesRedoPrivate`

The editor bundle itself is still built from the upstream `texteditors/atomic-editor` fork, while this package keeps the Swift hosting layer reusable across apps.
