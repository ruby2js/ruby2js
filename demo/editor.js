import {EditorView, keymap, highlightSpecialChars, drawSelection, highlightActiveLine, lineNumbers} from "@codemirror/view"
import {EditorState} from "@codemirror/state"
import {StreamLanguage, indentOnInput, bracketMatching, syntaxHighlighting, defaultHighlightStyle} from "@codemirror/language"
import {ruby} from "@codemirror/legacy-modes/mode/ruby"
import {javascript} from "@codemirror/lang-javascript"
import {history, historyKeymap, defaultKeymap} from "@codemirror/commands"
import {closeBrackets, closeBracketsKeymap} from "@codemirror/autocomplete"
import {searchKeymap, highlightSelectionMatches} from "@codemirror/search"
import {lintKeymap} from "@codemirror/lint"

// Custom setup based on basicSetup, but excluding autocompletion and folding
// which aren't useful for this demo use case
const setup = [
  lineNumbers(),
  highlightSpecialChars(),
  history(),
  drawSelection(),
  EditorState.allowMultipleSelections.of(true),
  indentOnInput(),
  syntaxHighlighting(defaultHighlightStyle, {fallback: true}),
  bracketMatching(),
  closeBrackets(),
  highlightActiveLine(),
  highlightSelectionMatches(),
  keymap.of([
    ...closeBracketsKeymap,
    ...defaultKeymap,
    ...searchKeymap,
    ...historyKeymap,
    ...lintKeymap
  ])
]

globalThis.CodeMirror = class {
  static rubyEditor(parent, notify=null) {
    return new EditorView({
      state: EditorState.create({
        extensions: [
          setup,
          StreamLanguage.define(ruby),
          EditorView.updateListener.of(update => {
            if (notify && update.docChanged) {
              notify(update.state.doc.toString())
            }
          })
        ]
      }),
      parent
    })
  }

  static jsEditor(parent) {
    return new EditorView({
      state: EditorState.create({
        doc: 'content',
        extensions: [
          setup,
          javascript({ jsx: true }),
          EditorView.editable.of(false)
        ]
      }),
      parent
    })
  }
}

document.body.dispatchEvent(new CustomEvent('CodeMirror-ready'))
