# CodeMirrorAtomic Bundle

This folder contains the shipped Atomic CodeMirror runtime used by the Swift wrapper in this repository.

It is a checked-in build artifact, not the main Atomic development workspace.

## Source Of Truth

Atomic source changes should be made and verified in the separate harness app / integration workspace.

After verification there, sync the updated runtime files into this folder.

## Required Companion File

Whenever you refresh the bundle here, also update:

- `ATOMIC_BUNDLE_SOURCE.json`

That file records the upstream repository, commit SHA, sync date, and reason for the update.

## Files Used At Runtime

- `index.html`
- `editor.js`
- `editor.bundle.js`
- `editor.bundle.css`
