## 1. Tree construction from ASDF

- [x] 1.1 Add `%path-key (p)` (canonical truename/namestring string) and
  `%open-editor-keys (app)` (keys of all file-backed editor windows) to
  `examples/tvlisp.lisp`.
- [x] 1.2 Add `%project-file-text (path open-keys)` rendering a file leaf label
  with a filled bullet when open, hollow otherwise.
- [x] 1.3 Add `%component-node (comp open-keys)`: source file → leaf node with
  `data` = pathname; module → expandable node over recursively-built children;
  other component types skipped.
- [x] 1.4 Add `%node-file-paths (node)` collecting all source pathnames under a
  node, and `%depends-node (sys)` listing `asdf:system-depends-on` names.
- [x] 1.5 Add `%system-tree (sysname open-keys)` building the root node (name,
  `*loaded` marker, file count) over the module/file children plus the
  depends-on node, wrapped in `handler-case` to return NIL on unreadable systems.
- [x] 1.6 Add `%pick-system (title)` reusing the `do-systems` picker style
  (registered systems, `*` for loaded), returning the bare name.

## 2. Project window and actions

- [x] 2.1 Add command constant `+cm-project+`.
- [x] 2.2 Define `tproject-window (twindow)` with app/sysname/outline slots.
- [x] 2.3 Add `%project-open-file (app path &optional focusp)` returning
  `(values window status)` with status `:focused` / `:opened` / `:missing`,
  reusing an existing window for the path and skipping files not on disk.
- [x] 2.4 Add `%project-refresh (w)` (rewrite leaf bullets in place, update
  scroller limit, `redraw` the desktop) and `%project-rebuild (w)` (re-read the
  system from ASDF and replace the roots).
- [x] 2.5 Add `%project-open-node (w)`: open every file under the focused node,
  reuse already-open ones, cascade the new windows with `move-to`, refresh, and
  summarize counts. (Count the opened list with non-destructive `reverse`, not
  `nreverse`.)
- [x] 2.6 Add `%project-close-node (w)`: close every editor window for files
  under the focused node via `close-window` (inheriting the unsaved-changes
  `valid-p` prompt), iterating a copied window list, and summarize the count.
- [x] 2.7 Add the `tproject-window` `handle-event`: open/focus on the
  `+cm-outline-item-selected+` broadcast; O / C / R on character keys; otherwise
  `call-next-method`.
- [x] 2.8 Add `do-project (app)`: pick a system, build the tree, open the project
  window with a `toutline` + scrollbar, or message when components can't be read.

## 3. Menu and dispatch wiring

- [x] 3.1 Add the "Open pro~j~ect..." `menu-item` (`+cm-project+`) under File,
  near "Open in editor".
- [x] 3.2 Add the command-dispatch clause routing `+cm-project+` → `do-project`.

## 4. Verification

- [x] 4.1 Load clean: `asdf:load-system :tvision/examples/tvlisp` with no new
  warnings; `make tvlisp` builds.
- [x] 4.2 In the running TUI: open the project for `tvision`, confirm the tree
  shows the `src/` module and 36 source files with hollow bullets.
- [x] 4.3 Enter on a file opens it and flips its bullet to filled; O on the root
  opens all files ("Opened 36 files (0 already open)"); reuse confirmed ("Opened
  35 files (1 already open)" after one was open); C on the root closes them
  ("Closed 36 windows").
- [x] 4.4 Editing a file then closing via C raises the "unsaved changes — save
  before closing?" prompt; cancelling leaves the file on disk untouched.
