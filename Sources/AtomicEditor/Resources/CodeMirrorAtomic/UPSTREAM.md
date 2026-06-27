# Atomic Editor Upstream Notes

This directory contains compiled Atomic/CodeMirror assets used by the iOS app.
The files `editor.bundle.js` and `editor.bundle.css` are generated artifacts.
Do not hand-edit them as the source of truth.

This repo intentionally does not vendor the Atomic source tree. The editable
source of truth lives in the separate Atomic harness app/repository. Make
changes there, rebuild the bundle, then copy the generated assets back here.

Rebuild the bundle from:

- upstream Atomic source in the harness repo: `ReessKennedy/atomic-editor`
- local WKWebView React host bridge: `Source/ios-host-entry.tsx`

Current source-side changes to carry upstream:

- `src/table-widget.ts`: `TableWidget` should override `get editable()` and
  return `true`. The widget contains editable table-cell descendants; without
  this override, CodeMirror may mark the widget DOM as non-editable, which can
  make table cells impossible to edit in WKWebView.
- `src/table-widget.ts`: table cell source taps should focus the inner
  `contenteditable` element and place the caret from event coordinates on
  `pointerdown`, `mousedown`, and `touchstart`. WKWebView can otherwise treat
  the whole block replacement widget as the selectable/editable target.
- `src/table-widget.ts` and `src/styles/inline-preview.css`: when the embedded
  host sets `window.__ATOMIC_TABLE_TEXT_INPUT_MODE__ = true`, table cells should
  swap from the `contenteditable` DOM editor to a real text input while keeping
  the rendered markdown preview in the resting state. This is a WKWebView /
  Catalyst-specific fallback path for cases where `contenteditable` resolves the
  hit correctly but still fails to activate a valid native text-input session.
- `src/table-widget.ts` and `Source/ios-host-entry.tsx`: the embedded app may
  instead set `window.__ATOMIC_TABLE_READONLY_MODE__ = true` to render Markdown
  tables without attempting any in-cell editing. In this mode, table links can
  still open, but the table should no longer advertise itself as an editable tap
  target through the host bridge.

These changes are captured in
`Source/patches/table-widget-wkwebview-cell-focus.patch`.
The task-checkbox size adjustment is captured in
`Source/patches/inline-preview-checkbox-scale.patch`.
The React host integration patch is captured in
`Source/patches/atomic-react-editable-handle.patch`.

When updating Atomic for this app:

1. Update the Atomic harness repo.
2. Apply `Source/patches/table-widget-wkwebview-cell-focus.patch` if it is not
   upstream yet.
3. Apply `Source/patches/inline-preview-checkbox-scale.patch` if it is not
   upstream yet.
4. Apply `Source/patches/atomic-react-editable-handle.patch` if it is not
   upstream yet.
5. Bundle `Source/ios-host-entry.tsx` against that Atomic source. The host
   currently opts into read-only table rendering by setting
   `window.__ATOMIC_TABLE_READONLY_MODE__ = true` and disabling the text-input
   fallback.
6. Replace the compiled files in this directory.
7. Keep the bundle version marker in sync so the app can log which Atomic build
   is embedded.
8. Re-test table cell editing and fenced-code syntax highlighting on iOS and
   Mac Catalyst.
