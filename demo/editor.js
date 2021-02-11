


import {EditorView} from "@codemirror/view"
import {StreamLanguage} from "@codemirror/stream-parser"
import {ruby} from "@codemirror/legacy-modes/mode/ruby"

// following is from basicSetup, but it specifically EXCLUDES autocompletion
// because, frankly, it is annoying.
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
  foldGutter(),
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
    ...foldKeymap,
    ...commentKeymap,
    // ...completionKeymap,
    ...lintKeymap
  ])
]

// create an editor below the textarea, then hide the textarea
let textarea = document.querySelector('textarea.ruby');
let editorDiv = document.createElement('div');
editorDiv.classList.add('editor');
textarea.parentNode.insertBefore(editorDiv, textarea.nextSibling);
textarea.style.display = 'none';

// create an editor below the textarea, then hide the textarea
let editor = new EditorView({
  state: EditorState.create({
    extensions: [
      setup,  
      StreamLanguage.define(ruby),
      EditorView.updateListener.of(update => {
        if (update.docChanged) {
          textarea.value = update.state.doc.toString();
          let event = new MouseEvent('click', { bubbles: true, cancelable: true, view: window });
          document.querySelector('input[type=submit]').dispatchEvent(event)
        }
      })
    ]
  }),
  parent: editorDiv
});

// focus on the editor
editor.focus();

// first submit may come from the livedemo itself; if that occurs
// copy the textarea value into the editor
let submit = document.querySelector('input[type=submit]');
submit.addEventListener('click', event => {
  if (!textarea.value) return;
  if (editor.state.doc.length) return;

  editor.dispatch({
    changes: {from: 0, to: editor.state.doc.length, insert: textarea.value}
  })
}, {once: true});
