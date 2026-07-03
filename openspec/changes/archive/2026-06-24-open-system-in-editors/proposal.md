## Why

Working on an ASDF system in tvlisp today means opening its files one at a time
through the file dialog — tedious for a system with a dozen source files, and
easy to lose track of which files belong to the system. There is no inverse
either: tidying up means hunting down and closing each editor window by hand.
A single place to *see* a system's files and open/close them as a group turns a
multi-minute chore into a couple of keystrokes.

## What Changes

- Add an **Open project...** command (File menu) that, given a registered ASDF
  system, opens a **project window**: a collapsible tree of the system's
  components — modules and their source files — built on the existing `toutline`
  widget. Open files are marked with a filled bullet (`●`), closed ones with a
  hollow bullet (`○`); a `depends-on (N)` node lists the system's dependencies.
- In the project window:
  - **Enter** on a file opens it in an editor window (or focuses its window if
    already open); the bullet updates.
  - **O** opens *every* source file under the focused node (whole system, a
    module, or a single file), cascading the new windows and reusing files that
    are already open.
  - **C** closes every editor window backed by a file under the focused node, in
    one step, honoring the existing per-window "unsaved changes — save before
    closing?" prompt.
  - **R** re-reads the system from ASDF (picks up `.asd` edits) and rebuilds the
    tree.
- Add a `+cm-project+` command constant, a File-menu entry, and one
  command-dispatch clause.
- Report a short summary after bulk open/close (e.g. "Opened 35 files (1 already
  open)", "Closed 36 windows").

This supersedes the originally-proposed pair of bare "Open system" / "Close
system" commands: the tree window is the UI primitive, and "open/close the whole
thing" is one key (O / C) on the root node rather than a separate command. The
tree's per-node scoping (operate on the system, a module, or one file) and the
visible open/closed markers fell out of using `toutline`, and they dissolve the
"which window belongs to which system" and "what counts as the system" questions
raised during exploration.

Non-goals: this does not load/compile the system (Lisp ▸ Systems already does
that), does not change the session save/restore format, and does not persist
per-window system membership (Close re-derives the file set from the system's
current components, and a node only ever closes the windows for files it owns).

## Capabilities

### New Capabilities
- `system-editor-windows`: Browsing an ASDF system as a tree of its source files
  in a project window, and opening/closing those files in editor windows — singly
  (Enter) or in bulk per tree node (O / C) — including how the tree is derived
  from ASDF components, how open vs. closed files are shown, how already-open and
  missing/unreadable files are handled, how opened windows are arranged, and how
  unsaved changes are handled on close.

### Modified Capabilities
<!-- None: openspec/specs/ is empty; no existing requirements change. -->

## Impact

- **Code**: `examples/tvlisp.lisp` only — a `tproject-window` class, a tree
  builder over ASDF components, open/close/refresh helpers, a `+cm-project+`
  constant, one File-menu `menu-item`, and one clause in the command dispatch.
- **Reuses existing infrastructure**: the `toutline` collapsible-tree widget
  (also used by the inspector and profiler), `make-edit-window` / `insert` /
  `focus`, `close-window` (already runs the unsaved-changes `valid-p` prompt),
  `desktop-windows` / `editor-window-editor` / `editor-filename` for matching
  open buffers, `move-to` for cascading, `redraw` for z-order-safe repaints, and
  the `do-systems` picker style for system selection.
- **Dependencies**: none new — tree construction uses ASDF (already a hard
  dependency).
- **Risk**: low and additive. The only outward effect is opening/closing windows;
  closing routes through the existing save-prompt path so no unsaved work is lost
  silently.
