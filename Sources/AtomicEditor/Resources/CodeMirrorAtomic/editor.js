import { EditorState, EditorSelection, Compartment } from "https://esm.sh/@codemirror/state@6.5.2";
import {
  EditorView,
  drawSelection,
  dropCursor,
  highlightActiveLine,
  highlightSpecialChars,
  keymap,
  rectangularSelection,
} from "https://esm.sh/@codemirror/view@6.38.8";
import { indentOnInput } from "https://esm.sh/@codemirror/language@6.12.3";
import { closeBrackets, closeBracketsKeymap } from "https://esm.sh/@codemirror/autocomplete@6.20.0";
import {
  defaultKeymap,
  history,
  historyKeymap,
  indentWithTab,
} from "https://esm.sh/@codemirror/commands@6.10.0";
import { markdown, markdownKeymap, markdownLanguage } from "https://esm.sh/@codemirror/lang-markdown@6.5.0";
import { search, searchKeymap } from "https://esm.sh/@codemirror/search@6.5.11";
import { tags as t } from "https://esm.sh/@lezer/highlight@1.2.3";
import {
  atomicEditorTheme,
  atomicMarkdownSyntax,
} from "https://esm.sh/gh/texteditors/atomic-editor@9800cb18f9945567c30069a8536c6177d73f14e7/src/atomic-theme.ts?deps=@codemirror/language@6.12.3,@codemirror/view@6.38.8,@lezer/highlight@1.2.3";
import {
  autoCloseCodeFence,
  extendEmphasisPair,
} from "https://esm.sh/gh/texteditors/atomic-editor@9800cb18f9945567c30069a8536c6177d73f14e7/src/edit-helpers.ts?deps=@codemirror/state@6.5.2,@codemirror/view@6.38.8";
import { imageBlocks } from "https://esm.sh/gh/texteditors/atomic-editor@9800cb18f9945567c30069a8536c6177d73f14e7/src/image-blocks.ts?deps=@codemirror/language@6.12.3,@codemirror/state@6.5.2,@codemirror/view@6.38.8,@lezer/common@1.2.3";
import { inlinePreview } from "https://esm.sh/gh/texteditors/atomic-editor@9800cb18f9945567c30069a8536c6177d73f14e7/src/inline-preview.ts?deps=@codemirror/language@6.12.3,@codemirror/state@6.5.2,@codemirror/view@6.38.8,@lezer/common@1.2.3";
import { tables } from "https://esm.sh/gh/texteditors/atomic-editor@9800cb18f9945567c30069a8536c6177d73f14e7/src/table-widget.ts?deps=@codemirror/language@6.12.3,@codemirror/state@6.5.2,@codemirror/view@6.38.8,@lezer/common@1.2.3";
import { ATOMIC_CODE_LANGUAGES } from "https://esm.sh/gh/texteditors/atomic-editor@9800cb18f9945567c30069a8536c6177d73f14e7/src/code-languages.ts?deps=@codemirror/language@6.12.3,@codemirror/lang-cpp@6.0.3,@codemirror/lang-css@6.3.1,@codemirror/lang-go@6.0.1,@codemirror/lang-html@6.4.11,@codemirror/lang-java@6.0.2,@codemirror/lang-javascript@6.2.5,@codemirror/lang-json@6.0.2,@codemirror/lang-markdown@6.5.0,@codemirror/lang-php@6.0.2,@codemirror/lang-python@6.2.1,@codemirror/lang-rust@6.0.2,@codemirror/lang-sql@6.10.0,@codemirror/lang-xml@6.1.0,@codemirror/lang-yaml@6.1.3,@codemirror/legacy-modes@6.5.2";

const HighlightDelim = { resolve: "Highlight", mark: "HighlightMark" };
let Punctuation = /[!"#$%&'()*+,\-.\/:;<=>?@\[\\\]^_`{|}~\xA1\u2010-\u2027]/;

try {
  Punctuation = new RegExp("[\\p{S}|\\p{P}]", "u");
} catch {
  // Older runtimes fall back to the ASCII+Latin punctuation set above.
}

function parseHighlight(cx, next, pos) {
  if (next !== 61 || cx.char(pos + 1) !== 61 || cx.char(pos + 2) === 61) {
    return -1;
  }

  const before = cx.slice(pos - 1, pos);
  const after = cx.slice(pos + 2, pos + 3);
  const spacedBefore = /\s|^$/.test(before);
  const spacedAfter = /\s|^$/.test(after);
  const punctBefore = Punctuation.test(before);
  const punctAfter = Punctuation.test(after);

  return cx.addDelimiter(
    HighlightDelim,
    pos,
    pos + 2,
    !spacedAfter && (!punctAfter || spacedBefore || punctBefore),
    !spacedBefore && (!punctBefore || spacedAfter || punctAfter),
  );
}

const highlightMarkdown = {
  defineNodes: [
    {
      name: "Highlight",
      style: t.special(t.content),
    },
    {
      name: "HighlightMark",
      style: t.processingInstruction,
    },
  ],
  parseInline: [
    {
      name: "Highlight",
      parse: parseHighlight,
      after: "Strikethrough",
    },
  ],
};

const root = document.getElementById("editor-root");
const editableCompartment = new Compartment();

let editorView = null;

function currentBridge() {
  return window.webkit?.messageHandlers?.codeMirrorAtomicBridge;
}

function postMessage(type, extras = {}) {
  currentBridge()?.postMessage({ type, ...extras });
}

function copiedRangeForState(state) {
  const parts = [];
  const ranges = [];
  let copiedAnySelection = false;
  for (const range of state.selection.ranges) {
    if (range.empty) {
      continue;
    }
    copiedAnySelection = true;
    parts.push(state.sliceDoc(range.from, range.to));
    ranges.push({ from: range.from, to: range.to });
  }

  if (copiedAnySelection) {
    return { text: parts.join(state.lineBreak), ranges, linewise: false };
  }

  const seenLines = new Set();
  for (const range of state.selection.ranges) {
    const line = state.doc.lineAt(range.from);
    if (seenLines.has(line.number)) {
      continue;
    }
    seenLines.add(line.number);
    parts.push(line.text);
    ranges.push({ from: line.from, to: Math.min(state.doc.length, line.to + 1) });
  }
  return { text: parts.join(state.lineBreak), ranges, linewise: true };
}

function replaceSelectionText(text, userEvent) {
  if (!editorView) {
    return;
  }
  const changes = editorView.state.replaceSelection(text);
  editorView.dispatch(changes, {
    userEvent,
    scrollIntoView: true,
  });
}

function deleteRanges(ranges) {
  if (!editorView || ranges.length === 0) {
    return;
  }
  editorView.dispatch({
    changes: ranges.map((range) => ({
      from: range.from,
      to: range.to,
      insert: "",
    })),
    selection: EditorSelection.cursor(ranges[0].from),
    userEvent: "delete.cut",
    scrollIntoView: true,
  });
}

function editableExtensions(isEditable) {
  return [
    EditorView.editable.of(Boolean(isEditable)),
    EditorState.readOnly.of(!Boolean(isEditable)),
  ];
}

function baseExtensions(config) {
  return [
    highlightSpecialChars(),
    history(),
    drawSelection(),
    dropCursor(),
    EditorState.allowMultipleSelections.of(true),
    indentOnInput(),
    rectangularSelection(),
    highlightActiveLine(),
    closeBrackets(),
    extendEmphasisPair,
    autoCloseCodeFence,
    EditorView.lineWrapping,
    search({ top: true }),
    markdown({
      base: markdownLanguage,
      codeLanguages: [...ATOMIC_CODE_LANGUAGES],
      extensions: highlightMarkdown,
    }),
    markdownLanguage.data.of({
      closeBrackets: { brackets: ["(", "[", "{", "'", "\"", "*", "_", "`"] },
    }),
    atomicMarkdownSyntax,
    atomicEditorTheme,
    editableCompartment.of(editableExtensions(config.isEditable)),
    keymap.of([
      ...closeBracketsKeymap,
      ...historyKeymap,
      ...searchKeymap,
      ...markdownKeymap,
      indentWithTab,
      ...defaultKeymap,
    ]),
    tables(),
    imageBlocks(),
    inlinePreview(),
    EditorView.contentAttributes.of({
      autocapitalize: "sentences",
      autocomplete: "off",
      autocorrect: "off",
      spellcheck: "false",
    }),
    EditorView.updateListener.of((update) => {
      if (update.focusChanged) {
        postMessage("focusChanged", { isFocused: update.view.hasFocus });
      }
      if (!update.docChanged) {
        return;
      }
      postMessage("textChange", { text: update.state.doc.toString() });
    }),
    EditorView.domEventHandlers({
      keydown(event, view) {
        if (!(event.metaKey || event.ctrlKey) || event.altKey) {
          return false;
        }
        const key = event.key.toLowerCase();
        if (key === "c") {
          const { text } = copiedRangeForState(view.state);
          if (!text) {
            return false;
          }
          postMessage("writeClipboard", { text });
          event.preventDefault();
          return true;
        }
        if (key === "x") {
          const { text, ranges } = copiedRangeForState(view.state);
          if (!text) {
            return false;
          }
          postMessage("writeClipboard", { text });
          deleteRanges(ranges);
          event.preventDefault();
          return true;
        }
        if (key === "v") {
          postMessage("readClipboard");
          event.preventDefault();
          return true;
        }
        return false;
      },
      copy(event, view) {
        const { text } = copiedRangeForState(view.state);
        if (!text) {
          return false;
        }
        postMessage("writeClipboard", { text });
        return false;
      },
      cut(event, view) {
        const { text } = copiedRangeForState(view.state);
        if (!text) {
          return false;
        }
        postMessage("writeClipboard", { text });
        return false;
      },
      paste(event) {
        const pastedText = event.clipboardData?.getData("text/plain") ?? "";
        if (!pastedText) {
          postMessage("readClipboard");
          event.preventDefault();
          return true;
        }
        return false;
      },
    }),
    EditorView.theme({
      "&": {
        height: "100%",
        fontSize: "var(--atomic-editor-body-size)",
      },
      ".cm-scroller": {
        overflow: "auto",
      },
    }),
  ];
}

function applyTheme(config) {
  const colors = config.colors ?? {};
  const style = document.documentElement.style;

  document.documentElement.dataset.theme = config.theme === "light" ? "light" : "dark";

  style.setProperty("--atomic-editor-font", config.fontFamily ?? "system-ui");
  style.setProperty("--atomic-editor-font-mono", config.codeFontFamily ?? "ui-monospace");
  style.setProperty("--atomic-editor-body-size", `${config.fontSizePx ?? 17}px`);
  style.setProperty("--atomic-editor-body-leading", `${config.lineHeight ?? 1.6}`);
  style.setProperty("--atomic-editor-measure", config.measure ?? "70ch");
  style.setProperty("--atomic-editor-bg", colors.background ?? "#111827");
  style.setProperty("--atomic-editor-bg-panel", colors.panel ?? "#1f2937");
  style.setProperty("--atomic-editor-bg-surface", colors.surface ?? "#374151");
  style.setProperty("--atomic-editor-border", colors.border ?? "#4b5563");
  style.setProperty("--atomic-editor-fg", colors.foreground ?? "#f9fafb");
  style.setProperty("--atomic-editor-fg-muted", colors.muted ?? "#9ca3af");
  style.setProperty("--atomic-editor-fg-faint", colors.faint ?? "#6b7280");
  style.setProperty("--atomic-editor-accent", colors.accent ?? "#2563eb");
  style.setProperty("--atomic-editor-accent-bright", colors.accentBright ?? colors.accent ?? "#3b82f6");
  style.setProperty("--atomic-editor-link", colors.link ?? colors.accent ?? "#2563eb");
  style.setProperty("--atomic-editor-link-hover", colors.linkHover ?? colors.link ?? "#1d4ed8");
  style.setProperty("--atomic-editor-code-bg", colors.codeBackground ?? colors.surface ?? "#111827");
  style.setProperty("--atomic-editor-selection-bg", colors.selection ?? "#2563eb44");
  style.setProperty("--atomic-editor-search-bg", colors.search ?? "#2563eb33");
  style.setProperty("--atomic-editor-search-bg-active", colors.searchActive ?? "#2563eb66");
}

function replaceDocument(nextText) {
  if (!editorView) {
    return;
  }

  const currentText = editorView.state.doc.toString();
  if (currentText === nextText) {
    return;
  }

  editorView.dispatch({
    changes: {
      from: 0,
      to: editorView.state.doc.length,
      insert: nextText,
    },
  });
}

function setEditable(isEditable) {
  if (!editorView) {
    return;
  }

  editorView.dispatch({
    effects: editableCompartment.reconfigure(editableExtensions(isEditable)),
  });
}

function createEditor(config) {
  if (!root) {
    postMessage("error", { message: "CodeMirror root element was not found." });
    return;
  }

  root.classList.add("atomic-cm-editor");
  editorView = new EditorView({
    parent: root,
    state: EditorState.create({
      doc: config.text ?? "",
      extensions: baseExtensions(config),
    }),
  });
  postEditorStatus("configured");
}

window.AtomicEditorHost = {
  configure(config) {
    applyTheme(config);
    if (!editorView) {
      createEditor(config);
      return;
    }

    setEditable(config.isEditable);
    replaceDocument(config.text ?? "");
    postEditorStatus("configured");
  },
  focus() {
    editorView?.focus();
  },
  blur() {
    editorView?.contentDOM?.blur();
  },
  pasteFromHostClipboard(text) {
    replaceSelectionText(text ?? "", "input.paste");
  },
};

function postEditorStatus(type) {
  requestAnimationFrame(() => {
    postMessage(type, {
      textLength: editorView?.state.doc.length ?? 0,
      rootWidth: root?.clientWidth ?? 0,
      rootHeight: root?.clientHeight ?? 0,
      editorCount: document.querySelectorAll(".cm-editor").length,
    });
  });
}

window.addEventListener("error", (event) => {
  postMessage("error", {
    message: event.message,
    filename: event.filename,
    line: event.lineno,
    column: event.colno,
  });
});

window.addEventListener("unhandledrejection", (event) => {
  postMessage("error", { message: String(event.reason ?? "unknown rejection") });
});

postMessage("ready");
