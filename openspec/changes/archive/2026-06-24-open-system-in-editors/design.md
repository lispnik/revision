## Context

tvlisp (`examples/tvlisp.lisp`) is a single-file Turbo Vision Lisp IDE on SBCL.
Editor windows are `teditor-window` instances created by
`make-edit-window (bounds &key title filename)` (`src/textview.lisp:1311`), which
returns `(values window editor)`; the window is added with `insert` and focused
with `focus`. Each editor's backing file is read via `editor-filename` on its
`editor-window-editor`.

The feature is realized as the "project window" (Mock A from exploration). The
pieces it builds on already exist:
- **`toutline`** (`src/outline.lisp`) — a collapsible tree view (`tscroller`)
  used by the inspector (`object->outline`) and the profiler call-tree. Nodes are
  `make-outline-node (text &optional children data setter)`; `data` carries an
  arbitrary payload. The widget draws `+`/`-`/leaf markers, handles
  arrows/Home/End/Enter/Space, folds on Enter for parent nodes, and on a leaf
  fires a `+cm-outline-item-selected+` broadcast to its owner window.
- **Window wrapper pattern** — `tcalltree-window` shows the idiom: a `twindow`
  subclass whose `handle-event` intercepts a broadcast (item activated) and
  specific character keys, falling through to `call-next-method` so the embedded
  view still gets arrows/Enter.
- **`do-systems`** already picks an ASDF system from `asdf:registered-systems`
  with `asdf:already-loaded-systems` markers.
- **`close-window`** (`src/window.lisp:49`) calls `(valid-p w +cm-close+)`; the
  `teditor-window` `valid-p` method shows the unsaved-changes prompt, so closing
  programmatically inherits the save guard.

## Goals / Non-Goals

**Goals:**
- One window shows an ASDF system's source files as a navigable tree.
- Open a single file (Enter), or all files under any node (O); close all under a
  node (C); refresh from ASDF (R).
- Show open vs. closed files; reuse already-open files; skip missing files.
- Closing honors the existing unsaved-changes prompt.
- Contained to `examples/tvlisp.lisp`, additive, low-risk.

**Non-Goals:**
- Loading/compiling the system (Lisp ▸ Systems already does that).
- Persisting per-window "system membership" — a node closes only the windows for
  the files it currently owns; Close re-derives that set from ASDF.
- Changing session save/restore.
- A split tree+editor preview pane (Mock C) — out of scope.

## Decisions

### Tree window built on `toutline`, not bare commands

The original proposal was two flat commands ("Open system", "Close system").
Exploration landed on a tree window instead, because `toutline` already provides
folding, scrolling, and per-node focus — so "open/close the whole system" becomes
O/C on the root node, while the same keys on a module or file scope the action
naturally. This dissolved two open questions: per-window system membership (the
focused node *is* the scope) and "what counts as the system" (dependencies are a
separate, collapsible `depends-on` node you choose to expand).

- **Alternative — two modal commands with system pickers**: simpler, but no
  visibility into what's open, no sub-system/module scoping, and Close needed a
  separate membership story. Rejected once `toutline` reuse was clear.

### Deriving the tree: recursive `component-children`

Walk the system's ASDF component graph directly:
`(asdf:component-children comp)` recursively — a component that `(typep c
'asdf:source-file)` becomes a leaf node whose `data` is `(asdf:component-pathname
c)`; a `(typep c 'asdf:module)` becomes an expandable node over its children;
anything else is skipped. The system itself is the root (a system is an
`asdf:module` subtype, but it's labelled specially with its name, a `*loaded`
marker, and a file count). `asdf:system-depends-on` feeds a non-openable
`depends-on (N)` node.

- **Alternative — `asdf:required-components`** (the earlier design's choice):
  returns a flat component set and its keyword support varies by ASDF version. A
  flat list also loses the module structure the tree wants to show. Rejected in
  favor of the children walk, which preserves the `src/` → files hierarchy and
  uses only the long-stable `component-children` / `component-pathname` /
  `component-name` accessors.
- Enumeration is wrapped in `handler-case`/`ignore-errors`: a broken or
  unreadable system definition yields a "components could not be read" message,
  never a crash.

### Open/closed markers and refresh

A file leaf's label is `"● name"` when an editor backs it, `"○ name"` otherwise.
The open set is computed by normalizing each open editor's `editor-filename` and
each component pathname through a `%path-key` helper (`truename` when possible,
else `namestring`) and comparing the strings — robust to relative/symlinked
paths. Refresh walks the existing nodes and rewrites the leaf labels in place
(preserving fold state), then repaints.

Repaints use `redraw` on the desktop rather than `draw-view` on the project
window: opening/focusing a file moves it on top, and `redraw` repaints the whole
desktop in z-order, avoiding a covered project window painting over the editor.

### Close: by-path match through `close-window`

Close re-derives the focused node's file set, normalizes to path keys, and for
each open `teditor-window` whose `editor-filename` key is in the set calls
`close-window` — iterating a *copy* of the desktop window list, since closing
mutates it. Because `close-window` runs `valid-p`, a dirty window prompts
save/discard/cancel; cancel leaves that window open and the loop continues. The
count reported is the number of windows actually removed.

### Arrangement: cascade the newly opened windows only

Newly opened windows are repositioned with `move-to` at a stepped diagonal
offset, so they don't fully overlap, without disturbing the REPL or other
existing windows (the generic `cascade` would relayout everything).

## Risks / Trade-offs

- **ASDF accessor variance** → uses only `component-children` /
  `component-pathname` / `component-name` / `system-depends-on`, all long-stable;
  all enumeration is guarded so a bad system definition shows a message, not a
  crash.
- **Opening a large system spawns many windows** → could clutter the desktop;
  mitigated by the diagonal cascade and by the per-node scoping (open just a
  module). Acceptable since the user explicitly asked to open the whole system.
- **Path comparison mismatches** (relative vs absolute, symlinks) → both sides
  normalized via `%path-key` (`truename`/`namestring`) before comparing.
- **Closing mutates the window list mid-iteration** → iterate a copied list.
- **Unsaved-changes cancel mid-close** → intended; the summary reports the actual
  count closed.
- **Destructive `nreverse` on a counted list** → a bug caught in verification:
  reversing the opened-windows list in place corrupted its length for the summary
  count. Use non-destructive `reverse` when the list is also counted afterwards.

## Open Questions

- Should the menu entry live under File (chosen, as it opens editors) or also
  under Lisp ▸ Systems? Either satisfies the spec; File was chosen.
- A future enhancement could let Enter on a `depends-on` child open *that*
  system's project tree, but it's out of scope here.
