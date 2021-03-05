import {EditorView} from "@codemirror/view"
import {StreamLanguage} from "@codemirror/stream-parser"
import {ruby} from "@codemirror/legacy-modes/mode/ruby"
import {javascript} from "@codemirror/lang-javascript"

// following is from basicSetup, but it specifically EXCLUDES autocompletion
// because, frankly, it is annoying.  It also excludes folding partly because
// it is only available to non-legacy languages, and partly because it isn't
// all that useful for this use case.
import {keymap, highlightSpecialChars, drawSelection, highlightActiveLine} from "@codemirror/view"
import {EditorState, Prec} from "@codemirror/state"
import {history, historyKeymap} from "@codemirror/history"
import {foldGutter, foldKeymap} from "@codemirror/fold"
import {indentOnInput} from "@codemirror/language"
import {lineNumbers} from "@codemirror/gutter"
import {defaultKeymap} from "@codemirror/commands"
import {bracketMatching} from "@codemirror/matchbrackets"
import {closeBrackets, closeBracketsKeymap} from "@codemirror/closebrackets"
import {searchKeymap, highlightSelectionMatches} from "@codemirror/search"
import {autocompletion, completionKeymap} from "@codemirror/autocomplete"
import {commentKeymap} from "@codemirror/comment"
import {rectangularSelection} from "@codemirror/rectangular-selection"
import {defaultHighlightStyle} from "@codemirror/highlight"
import {lintKeymap} from "@codemirror/lint";

/// This is an extension value that just pulls together a whole lot of
/// extensions that you might want in a basic editor. It is meant as a
/// convenient helper to quickly set up CodeMirror without installing
/// and importing a lot of packages.
///
/// Specifically, it includes...
///
///  - [the default command bindings](#commands.defaultKeymap)
///  - [line numbers](#gutter.lineNumbers)
///  - [special character highlighting](#view.highlightSpecialChars)
///  - [the undo history](#history.history)
///  - [a fold gutter](#fold.foldGutter)
///  - [custom selection drawing](#view.drawSelection)
///  - [multiple selections](#state.EditorState^allowMultipleSelections)
///  - [reindentation on input](#language.indentOnInput)
///  - [the default highlight style](#highlight.defaultHighlightStyle)
///  - [bracket matching](#matchbrackets.bracketMatching)
///  - [bracket closing](#closebrackets.closeBrackets)
///  - [autocompletion](#autocomplete.autocompletion)
///  - [rectangular selection](#rectangular-selection.rectangularSelection)
///  - [active line highlighting](#view.highlightActiveLine)
///  - [selection match highlighting](#search.highlightSelectionMatches)
///  - [search](#search.searchKeymap)
///  - [commenting](#comment.commentKeymap)
///  - [linting](#lint.lintKeymap)
///
/// (You'll probably want to add some language package to your setup
/// too.)
///
/// This package does not allow customization. The idea is that, once
/// you decide you want to configure your editor more precisely, you
/// take this package's source (which is just a bunch of imports and
/// an array literal), copy it into your own code, and adjust it as
/// desired.
const setup = [
  lineNumbers(),
  highlightSpecialChars(),
  history(),
  // foldGutter(),
  drawSelection(),
  EditorState.allowMultipleSelections.of(true),
  indentOnInput(),
  Prec.fallback(defaultHighlightStyle),
  bracketMatching(),
  closeBrackets(),
  // autocompletion(),
  rectangularSelection(),
  highlightActiveLine(),
  highlightSelectionMatches(),
  keymap.of([
    ...closeBracketsKeymap,
    ...defaultKeymap,
    ...searchKeymap,
    ...historyKeymap,
    // ...foldKeymap,
    ...commentKeymap,
    // ...completionKeymap,
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
          javascript(),
          EditorView.editable.of(false)
        ]
      }),
      parent
    })
  }
}

document.body.dispatchEvent(new CustomEvent('CodeMirror-ready'))
