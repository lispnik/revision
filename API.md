# revision — public API reference

The exported symbols of the `revision` package, with their docstrings.  Generated from the live definitions by `revision:api-markdown` (run `make api`); do not edit by hand.

## Macros

**`define-command` (name (view event) &body body)**  — Define and register command NAME with an action over (VIEW EVENT).  A leading string in BODY (with forms following it) becomes the command's :DOC -- a one-line description surfaced in the generated keybinding reference.

**`defkeymap` (name (&optional parent) &body bindings)**  — Define a keymap NAME (optionally inheriting PARENT) from (KEYSYM COMMAND) pairs.

**`ignoring-errors` ((context) &body body)**  — Evaluate BODY like IGNORE-ERRORS -- returning NIL on any ERROR instead of propagating -- but first REVISION-LOG the condition under CONTEXT (a short string), so a swallowed failure on a persistence/desktop path stays diagnosable.

**`ui` (form)**  — Build a view tree declaratively; the structure is checked at macroexpansion.

**`with-fresh-context` ((&key root) &body body)**  — Run BODY on a fresh, isolated UI context (its own dirty flags, dirty-view set, and ROOT). INVALIDATE and any event loop inside BODY see only this context, so an embedded, headless, or under-test UI never dirties -- or is dirtied by -- the ambient application's context.

**`with-screen` ((&optional var) &body body)**  — Run BODY with an initialised screen, guaranteeing teardown on exit.

## Classes

**`button`**  — A focusable push button that performs its COMMAND on Enter, Space, or a click.

**`cluster`**  — A focusable checkbox (:CHECK) or radio-button (:RADIO) group; Space or a click toggles the item under the cursor.  See CLUSTER-VALUE for the selection.

**`command`**  — A named, reactive unit of behaviour: an ACTION closure over (VIEW EVENT) plus an ENABLED flag.  Reactive, so toggling ENABLED auto-repaints menus/buttons that show it. Invoked by name through PERFORM; keymaps and menus reference commands by NAME.

**`container`**  — A VIEW that holds SUBVIEWS: it draws each child, routes key events to its focused leaf, handles Tab/Shift-Tab focus movement, and hit-tests mouse events down the tree.  On the root window CONTAINER-FOCUS names the focused leaf anywhere in the subtree.

**`context`**  — One running UI instance's frame state: the invalidation flags the event loop consults each iteration plus the ROOT view (the modal background) they target.  Bound as *CONTEXT*; create a fresh one with WITH-FRESH-CONTEXT to isolate an embedded or headless UI.

**`desktop`**  — The IDE shell: a menu bar, a status bar, and a background hosting movable, resizable, overlapping windows.  Owns the single event loop and window Z-order.

**`dialog`**  — A modal top-level window run by EXEC-VIEW: on Accept it validates its fields and computes a result via VALUE-FN; on Cancel it returns :CANCEL.

**`editor-window`**  — A window hosting a TEXT-EDIT pane plus a status line, wiring the title, line:col indicator, find/replace prompts and Tab-completion around it.

**`event`**  — Base class for input/system events dispatched to views via HANDLE-EVENT.

**`html-view`**  — A scrollable HTML view: renders a tokenized/wrapped document with styled runs, focusable links, in-page anchors, and find-in-page.  Load content with SET-HTML.

**`input-line`**  — An editable single-line text field with optional validation and history recall.

**`key-event`**  — A key-press event; its (KEYSYM . MODIFIERS) form the token matched against keymaps.

**`keymap`**  — A layer of input bindings mapping (KEYSYM . MODS) tokens to command names, with an optional PARENT for inheritance.  Bindings are data -- introspectable and rebindable.

**`label`**  — Static text tied to a control (TLabel): its ~x~ Alt-mnemonic focuses the linked control, and it brightens while that control is focused.

**`list-box`**  — A scrollable, selectable flat list; Enter activates the selected item.

**`menu-bar`**  — The desktop's top pull-down menu bar: draws the titles and dropdowns from MENUS, handles hotkey/accelerator navigation, and invokes the selected item's command.

**`mouse-down`**  — A mouse button-press event (EVENT-DOUBLE is true for the 2nd click of a double-click).

**`mouse-event`**  — Base class for mouse events; EVENT-WHERE gives the pointer's cell position.

**`outline`**  — A collapsible tree view over OUTLINE-NODE trees, with lazy child loading. FOCUSED/TOP are reactive so mutating them auto-repaints.

**`outline-node`**  — One node of a collapsible outline/tree: its display TEXT, child nodes, current expansion state, an arbitrary DATA payload, and optional per-row COLOR, lazy LOADER, and DATA SETTER hooks.

**`persistent-class`**  — Metaclass for objects whose marked slots are saved and restored across sessions; see SAVE-OBJECT / LOAD-OBJECT.

**`reactive-class`**  — Metaclass whose instances invalidate the screen when a slot write CHANGES its value: an :around method on (SETF SLOT-VALUE-USING-CLASS) calls INVALIDATE, so views never repaint themselves -- mutating reactive state schedules one committed frame on the next loop, and a no-op write (same EQL value) schedules nothing.

**`row`**  — A horizontal layout container: children are placed left-to-right, each sized by its spec (:FILL shares the remaining columns, an integer fixes the column count).

**`screen`**  — The terminal driver's state: the off-screen back/front cell buffers, terminal size and cursor, pending input bytes and decoded events, and mouse-tracking state.  Stands in for Turbo Vision's THardwareInfo / TScreen.

**`scrollback`**  — An append-only, scrollable transcript view for REPLs and log/output panes.  Text streams in as arbitrary chunks (a partial trailing line waits in PENDING), the view auto-follows the tail unless scrolled back, printed results can be marked as clickable presentations, and an optional inline input line floats after the output.

**`session`**  — A small persisted model: the FILTER text and outline LINE are written to disk and restored on the next run.  TOUCHED is :transient — recomputed each run, never saved.

**`stack`**  — A vertical layout container: children are stacked top-to-bottom, each sized by its spec (:FILL shares the remaining rows, an integer fixes the row count).

**`static-text`**  — A non-focusable one-line text label, drawn in ROLE's colours.

**`status-bar`**  — The desktop's bottom bar: draws clickable action chips supplied by its PROVIDER thunk, plus any transient tool note right-aligned.

**`table-view`**  — A columnar table/grid viewer: a fixed header over scrollable, selectable data rows.  COLUMNS defines the (title, width, accessor) of each column; supports keyboard and mouse selection, the wheel, and the scroller protocol for frame scrollbars.

**`table-window`**  — A window whose scroll target is a TABLE-VIEW; the desktop saves and restores its scroll offset and selected row via the app's persistence methods.

**`text-edit`**  — A multi-line code-editing widget: a vector-of-lines buffer with a cursor, viewport scrolling, Shift/mark selection, an internal clipboard, snapshot undo/redo, incremental and regex find/replace, optional soft-wrap and a syntax-colour hook.

**`tpoint`**  — A 2-D screen coordinate: integer column X and row Y, 0-based with the origin at the top-left of the screen.

**`trect`**  — An axis-aligned rectangle given by two corner points: A (AX,AY) is the top-left corner, inclusive, and B (BX,BY) is the bottom-right corner, exclusive.

**`validation-error`**  — Signalled when a field or whole-dialog check fails.  The modal loop catches it, shows its MESSAGE, and keeps the dialog open so the user can correct the input.

**`view`**  — Root of the view hierarchy: a rectangular region that draws itself and handles events.  A reactive instance, so mutating a slot repaints; subclasses add HANDLE-EVENT and DRAW methods.  CONTAINER extends it with subviews.

**`wheel-event`**  — A mouse-wheel scroll event; EVENT-DELTA gives the scroll direction and magnitude.

**`window`**  — A framed, optionally desktop-managed top-level view: a titled container with a border, an optional frame scrollbar, and z-order/zoom state for the desktop.

## Generic functions

**`button-command` (object)**  — Command performed when the button is pressed (Enter/Space/click).

**`button-label` (object)**  — Text shown between the brackets, e.g. "OK" in [ OK ].

**`cluster-items` (object)**  — The list of item labels, one per line.

**`cluster-value` (object)**  — The selection: in :CHECK mode a sorted list of checked indices; in :RADIO mode the single chosen index (or NIL).

**`command-name` (object)**  — The symbol naming this command (its key in *COMMANDS* and in keymaps).

**`container-focus` (object)**  — On the root window, the focused focusable leaf anywhere in the subtree (else NIL).

**`context-menu` (view)**  — Right-click menu for VIEW: a list of (LABEL . THUNK), or NIL.

**`dialog-result` (object)**  — The dialog's outcome: the accepted value, or :CANCEL if dismissed.

**`draw` (view)**  — Render VIEW into the screen back buffer, within its bounds.

**`dt-windows` (object)**  — The hosted windows in back-to-front Z-order; the last is topmost/focused.

**`event-delta` (object)**  — Scroll amount/direction (negative = up, positive = down).

**`event-keysym` (object)**  — The key: a character, or a keyword for a special key (:up :enter :f1 …).

**`event-modifiers` (object)**  — Bitmask of held modifiers (+MD-CTRL+ / +MD-ALT+ / +MD-SHIFT+).

**`event-where` (object)**  — Cell position of the pointer (a TPOINT in screen coordinates).

**`focusable-p` (view)**  — True if VIEW can hold keyboard focus (a focusable leaf).  Default NIL; interactive widgets override it, and containers use it to enumerate focus stops.

**`frame-indicator` (view)**  — A short string a scroll-target view puts on its window's bottom frame, left of the horizontal scrollbar (classic TV's TIndicator).  NIL for none.

**`handle-event` (view event)**  — Dispatch EVENT to VIEW: the core (view x event) multimethod protocol.  The base VIEW turns a key event into a command via its keymap chain; subclasses add methods and set HANDLED-P once they consume it.  The default method ignores the event.

**`handled-p` (object)**  — Set true once a HANDLE-EVENT method consumes the event, stopping bubbling.

**`hv-on-link` (object)**

**`hv-on-status` (object)**

**`input-caret` (object)**  — Insertion-point column within TEXT (0 = before the first char).

**`input-history-id` (object)**  — Key into *INPUT-HISTORIES* enabling Up/Down recall of past entries, or NIL.

**`input-on-change` (object)**  — Closure (il) called whenever the text changes -- data binding.

**`input-text` (object)**  — The field's current contents; reactive, so edits repaint.

**`input-validator` (object)**  — A FIELD-VALIDATOR (or NIL): FILTER rejects keystrokes, CHECK validates the whole field on accept.

**`keymap-parent` (object)**  — Fallback keymap consulted when a token is unbound here (the inheritance chain).

**`layout` (view rect)**  — Assign VIEW (and its subtree) bounds within RECT.

**`list-items` (object)**  — The list of item strings displayed, one per row.

**`list-on-activate` (object)**  — Closure (lb item) called on Enter with the chosen item.

**`list-selected` (object)**  — Index of the currently highlighted item.

**`list-top` (object)**  — Index of the first visible row (vertical scroll offset).

**`outline-focused` (object)**  — Row index (into the flattened visible nodes) of the focused node.

**`outline-roots` (object)**  — List of top-level OUTLINE-NODE structures forming the tree.

**`outline-top` (object)**  — Index of the first visible row (the vertical scroll offset).

**`perform` (command view event)**  — Run COMMAND (a command object or its name) for VIEW/EVENT.

**`sb-follow` (object)**  — When true, the viewport auto-sticks to the tail as new text arrives.

**`sb-iactive` (object)**  — When true, a live inline input line floats after the output.

**`sb-icaret` (object)**  — Caret position (character index) within the inline input line.

**`sb-input` (object)**  — Text currently typed into the inline input line.

**`sb-iprompt` (object)**  — Prompt string shown before the inline input line.

**`sb-lines` (object)**  — Adjustable vector of committed transcript lines (one string per line).

**`sb-on-present` (object)**  — Callback (OBJECT) invoked when a presentation line is clicked, or NIL.

**`sb-on-submit` (object)**  — Callback (INPUT-STRING) invoked when Enter submits the inline input, or NIL.

**`sb-pending` (object)**  — The trailing partial line held until its newline arrives in a later chunk.

**`sb-top` (object)**  — Index of the first visible row (the vertical scroll offset).

**`scroll-hmax` (v)**

**`scroll-hpage` (v)**

**`scroll-hpos` (v)**

**`scroll-hto` (v pos)**

**`scroll-max` (v)**  — Maximum scroll offset (>= 0).

**`scroll-page` (v)**  — Number of visible rows.

**`scroll-pos` (v)**  — First visible row (the scroll offset).

**`scroll-to` (v pos)**  — Set the offset (clamped) and repaint.

**`serialize` (object)**  — A readable representation of OBJECT (see the notes above): readable atoms pass through, cons/vector/array/hash-table recurse, and persistent-class objects become (:object CLASS slot val ...) over their non-transient, bound slots.  Cycles and unserializable values SIGNAL.  Extend it with methods for an application's own types.

**`session-filter` (object)**  — The saved filter/type-ahead text, persisted across runs.

**`session-line` (object)**  — The saved outline line/cursor position, persisted across runs.

**`static-text-text` (object)**  — The string displayed on the single line; setting it repaints.

**`status-hints` (view)**  — The (LABEL . THUNK) action chips the focused VIEW contributes to the desktop status bar; specialize to offer context actions.  Default: none.

**`subviews` (object)**  — Child views in paint order (last paints on top); see ADD-SUBVIEW.

**`table-columns` (object)**  — Column specs, each a (TITLE WIDTH ACCESSOR) list; ACCESSOR maps a row to its cell value.

**`table-hleft` (object)**

**`table-rows` (object)**  — List of row objects, one per data row (the header is drawn separately).

**`table-selected` (object)**  — Index into ROWS of the currently selected/highlighted data row.

**`table-top` (object)**

**`te-anchor` (object)**  — Selection origin as a (LINE . COL) cons, or NIL when nothing is selected.

**`te-auto-close` (object)**  — When true, typing an opening ( [ or " auto-inserts the matching close.

**`te-colorizer` (object)**  — Optional syntax-highlight hook (LINE IN-STRING) -> (values ATTRS CARRY), or NIL.

**`te-completer` (object)**  — Per-editor completion hook (TE TOKEN) -> candidate strings; overrides *EDITOR-COMPLETIONS-FN*.

**`te-cx` (object)**  — Cursor column as a code-point index within the current line.

**`te-cy` (object)**  — Cursor line (0-based row index into the line vector).

**`te-evaluator` (object)**  — Per-editor eval hook (TE) for the Eval chip; overrides *EDITOR-EVAL-FN*.

**`te-filename` (object)**  — Pathname backing the buffer, or NIL for a scratch buffer.

**`te-indenter` (object)**  — Per-editor indent hook (TE) -> column for a fresh line; overrides *LISP-INDENTER*.

**`te-line-numbers` (object)**  — When true, show a line-number gutter (flat, non-wrapped mode only).

**`te-modified` (object)**  — T once the buffer has unsaved edits; cleared by save/load.

**`te-notes` (object)**  — Alist of (LINE . SEVERITY) compiler notes drawn as gutter markers.

**`te-paren-matcher` (object)**  — Per-editor bracket-match hook (TEXT OFFSET) -> match offset; overrides *PAREN-MATCHER*.

**`te-redo` (object)**  — Stack of redo snapshots, each a (LINES-LIST CY CX) list; newest first.

**`te-undo` (object)**  — Stack of undo snapshots, each a (LINES-LIST CY CX) list; newest first.

**`validation-message` (condition)**  — The user-facing message carried by a VALIDATION-ERROR condition.

**`view-bounds` (object)**  — The view's screen rectangle (a revision TRECT), assigned by LAYOUT.

**`view-key-hints` (view)**  — The (KEY-LABEL . DESCRIPTION) list of keys VIEW handles INTRINSICALLY -- inside its own HANDLE-EVENT rather than through a keymap.  Default: none.  A widget specializes this next to its HANDLE-EVENT, making the widget the single source of truth for its own keys; the keybinding reference and DESCRIBE-VIEW-KEYS read it.

**`view-keymap` (object)**  — The view's KEYMAP (or NIL); its chain turns key events into commands.

**`view-name` (object)**  — Optional symbol identifying the view, used by FIND-VIEW lookups.

**`view-owner` (object)**  — The containing view (NIL for a root window); walk it up via VIEW-ROOT.

**`window-dirty-p` (win)**  — Does WIN hold unsaved changes, so closing it should first prompt to save?  Default NIL; a document/editor window overrides it.

**`window-esc-dismissable-p` (win)**  — May Esc dismiss WIN?  Default T (transient windows -- pickers, output, dialogs -- close on Esc); a document/editor window overrides to NIL so Esc never silently discards it.

**`window-help` (object)**  — Help-topic keyword shown for this window on F1 / the Help menu.

**`window-kind` (object)**  — Builder keyword (e.g. :repl) identifying the window for desktop layout save/restore.

**`window-restore-state` (win state)**  — Apply STATE (as produced by WINDOW-SAVE-STATE) to the freshly-built WIN during layout restore.  Default: ignore.

**`window-save-state` (win)**  — A READ-able value capturing WIN's restorable state beyond its kind and geometry (or NIL for none).  The desktop persists it in the saved layout and hands it back to WINDOW-RESTORE-STATE on the freshly-rebuilt window next launch.

**`window-scroll-target` (object)**  — Scrollable child view whose position drives the window's frame scrollbar, or NIL.

**`window-title` (object)**  — The window's title, drawn centred in its top frame.

## Functions

**`add-laid` (c v spec)**  — Add view V to container C as a laid-out child governed by SPEC (an integer fixes its extent; :FILL shares the remainder).  Returns V.

**`add-subview` (c v)**  — Add view V as a child of container C (appended last, so it paints on top) and set V's owner to C.  Returns V.

**`all-focusables` (v)**  — List every focusable leaf in V's subtree, in depth-first paint order -- the window's Tab order.  Flattens nested layout containers so focus is a window-level property.

**`api-markdown`**  — Render the exported public API — every external symbol of :REVISION with its docstring, grouped by kind — as a Markdown reference.  Regenerated by `make api`.

**`async-children` (node view work &key (placeholder   …))**  — A non-blocking lazy loader for a slow OUTLINE-NODE: start WORK (a 0-arg thunk that may block -- a subprocess, a file read -- and returns a list of child nodes) on a worker thread, and return a single PLACEHOLDER child immediately.  DRAW therefore never blocks on the load (OUTLINE-ENSURE-CHILDREN calls the loader, sometimes mid-repaint); when WORK lands, its result replaces the placeholder and VIEW is repainted.  Use it as a node's LOADER:  (setf (outline-node-loader n)                 (lambda () (async-children n tree (lambda () (compute-children n)))))

**`attr-bg` (a)**  — The background colour index (0-7) of legacy DOS attribute A.

**`attr-fg` (a)**  — The foreground colour index (0-15) of legacy DOS attribute A.

**`attr-rgb-bg` (a)**  — The 24-bit packed background of an RGB attribute A.

**`attr-rgb-fg` (a)**  — The 24-bit packed foreground of an RGB attribute A.

**`attr-rgb-p` (a)**  — True when attribute A is a true-colour (RGB) attribute rather than a legacy 4-bit DOS attribute.

**`bind-key` (km spec command)**  — Bind SPEC (a keysym, a control char, or a (KEYSYM . MODS) cons) to command name COMMAND in keymap KM, normalising SPEC to its canonical token first.

**`char-width` (ch)**  — Display width of CH in terminal columns: 2 for East-Asian wide/fullwidth characters (CJK, most emoji), 1 otherwise.  ASCII and the low BMP fast-path to 1.

**`command-enabled-p` (command)**  — Is COMMAND enabled right now?  ENABLED is a boolean, or a predicate thunk evaluated on demand -- the single enablement check used by PERFORM (and available to menus / buttons), so a guarded command no longer needs a second, hand-rolled check.

**`context-dirty` (instance)**

**`context-dirty-views` (instance)**

**`context-full-redraw` (instance)**

**`context-root` (instance)**

**`copy-point` (p)**  — Return a fresh TPOINT with the same coordinates as P.

**`copy-rect` (r)**  — Return a fresh TRECT with the same corners as R.

**`ctrl` (ch)**  — A binding spec for Ctrl-CH: the (KEYSYM . MODS) cons (CH . +md-ctrl+).  Ctrl lives in the modifier bits -- TRANSLATE normalises the control char terminals send to this form -- so e.g. (ctrl #\o) matches the same token the driver produces for Ctrl-O.

**`describe-view-keys` (view)**  — Every key VIEW responds to, as (KEY-LABEL . DESCRIPTION): its intrinsic keys (VIEW-KEY-HINTS, handled inside its own HANDLE-EVENT) followed by the bindings from its keymap chain (each resolved to its command's doc).  The single place to answer "what does a key do for this view" across BOTH dispatch paths.  Keys it ignores bubble to its owner's keymap -- walk VIEW-OWNER for those.

**`deserialize` (form)**  — Reconstruct what SERIALIZE produced (SERIALIZE guarantees acyclic output, so this never needs cycle handling).

**`digits-validator`**  — A validator that allows only digit characters to be typed into the field.

**`disable-command` (command)**  — Mark the command named COMMAND disabled: PERFORM ignores it and its menu/keymap entries grey out.

**`drain-ui-callbacks`**  — Run (on the UI thread) every thunk posted since the last drain.

**`draw-text` (view col row string attr)**  — Write STRING at view-local (COL,ROW), clipped to VIEW's width.  Grapheme-aware: a multi-code-point cluster (skin-tone / ZWJ emoji, combining marks) is interned as one display unit, and a double-width glyph reserves its second cell with the +wide-cont+ sentinel (so the flush doesn't overwrite its right half).

**`dt-close-window` (dt win)**  — Close WIN on desktop DT: run its cleanup, remove it from the Z-order, and refocus.

**`dt-load-layout` (dt &optional (path (%desktop-file)))**  — Reopen the windows recorded in PATH at their saved positions.  Each is rebuilt by its registered builder and then handed its saved state via WINDOW-RESTORE-STATE.

**`dt-open` (dt kind-or-fn)**  — Open a window: KIND-OR-FN is a builder keyword (looked up in *WINDOW-BUILDERS* and recorded so the layout can be saved/restored) or a builder function (used directly, not persisted).  Cascade-positioned, focused on top.

**`dt-raise` (dt w)**  — Move window W to the top of desktop DT's Z-order, making it the focused window.

**`dt-refocus` (dt)**  — Keep the menu live only when no window is open.

**`dt-save-layout` (dt &optional (path (%desktop-file)))**  — Write the open windows -- kind, bounds, Z-order, and each window's own restorable state -- to PATH.  A window contributes state through WINDOW-SAVE-STATE: editors save their filename and any unsaved buffer text, the REPL its package + history, and so on, so relaunching restores the whole session.

**`dt-top` (dt)**  — The topmost (focused) window on desktop DT, or NIL when none are open.

**`enable-command` (command)**  — Re-enable COMMAND after a DISABLE-COMMAND.

**`exec-view` (dialog &key (width 48) (height 9))**  — Run DIALOG modally, centred over the current *ROOT* (drawn behind it), until it finishes; return its result value, or :CANCEL.

**`fail-validation` (message)**  — Signal a VALIDATION-ERROR carrying MESSAGE, rejecting the current dialog input and displaying MESSAGE to the user.

**`fill-row` (view col row width attr)**

**`filter-validator` (allowed)**  — Allow only characters in the string ALLOWED.

**`find-view` (root name)**  — Depth-first search for the subview named NAME, or NIL.  Names match by NAME string (see VIEW-NAME=), so a lookup works even when NAME is interned in another package.

**`flush-screen` (&optional (s *screen*))**  — Paint the changed cells of screen S to the terminal: diff the back buffer against the front buffer and emit only the cells that changed since the previous frame, then place the hardware cursor where a focused view asked for it.

**`focus-next` (root &optional (dir 1))**  — Move ROOT's focus to the next focusable leaf, cycling; DIR 1 advances (Tab), -1 goes back (Shift-Tab).  No-op when there are no focusable leaves.

**`fuzzy-filter` (query items &key (key #'identity))**  — ITEMS whose KEY fuzzy-matches QUERY, ranked best score first.  Empty QUERY returns ITEMS unchanged.

**`hide-cursor` (&optional (s *screen*))**  — Hide screen S's hardware cursor (takes effect on the next flush).

**`input-notify` (il)**  — Fire IL's ON-CHANGE closure (if any) to signal that the text changed.

**`invalidate` (&optional object slot)**  — Mark the current context (*CONTEXT*) dirty so its event loop commits a fresh frame next iteration.  When OBJECT is a VIEW whose geometry did not change, record it for a partial repaint (only the affected top window is redrawn); anything else -- a non-view, or a BOUNDS change that can vacate cells -- forces a full-screen redraw.  SLOT is the changed slot's name (NIL from explicit callers, which are treated as a localizable view change).

**`key-label` (token)**  — Human label for a (KEYSYM . MODS) keymap TOKEN, e.g. "Ctrl+C", "Shift+Del", "F2", "Alt+X", "Up".

**`keybinding-html` (&optional (ref (keybinding-reference)))**  — Render the keybinding reference (see KEYBINDING-REFERENCE) as HTML for the in-app help viewer, using the H1/H2/UL/LI/CODE vocabulary the help pages already use.

**`keybinding-markdown` (&optional (ref (keybinding-reference)))**  — Render the keybinding reference (see KEYBINDING-REFERENCE) as a Markdown document.

**`keybinding-reference`**  — A list of (SECTION-TITLE . ((KEY-LABEL . COMMAND) ...)) covering the menu accelerators, every named keymap (derived from the live keymaps), each widget's intrinsic keys (from its VIEW-KEY-HINTS, via *WIDGET-KEY-VIEWS*), and any application extras in *WIDGET-KEY-DOC*.

**`keymap-entries` (km)**  — Sorted list of (KEY-LABEL . COMMAND-NAME) for KM's own bindings (not inherited).

**`keymap-lookup` (km keysym &optional (mods 0) loose)**  — Command bound to KEYSYM+MODS in KM's chain.  Exact (keysym . mods) match by default. With LOOSE true, fall back to a modifier-insensitive (keysym . 0) binding when there is no exact match -- OFF by default, so a plain binding no longer silently swallows its modified variants (Ctrl-/Shift-<key> only fires a binding made for it).

**`lisp-colorize` (line in-string)**  — Colour LINE as Lisp: comments, strings, char literals, and :keywords. Return (values ATTRS END-IN-STRING).

**`list-scroll-fix` (lb)**  — Adjust LIST-TOP so the selected item stays within the visible rows.

**`load-object` (path)**  — Read and DESERIALIZE the object previously written to PATH by SAVE-OBJECT. Returns the reconstructed object, or NIL if PATH is missing or unreadable.

**`log-messages`**  — The recent diagnostic lines (oldest first) from the in-memory ring.

**`make-attr` (fg bg &optional (blink nil))**  — Build a legacy DOS attribute from foreground FG (0-15) and background BG (0-7).

**`make-color-dialog`**  — Visual colour customiser: pick a role, then a foreground and background from the swatch strips (with a live sample); Apply previews it on *THEME*.

**`make-context` (&key ((dirty dirty) nil) ((dirty-views dirty-views) 'nil)
  ((full-redraw full-redraw) t) ((root root) nil))**

**`make-doc-browser` (title html &optional base-url)**  — An HTML browser over arbitrary HTML; with *URL-FETCH-FN* set, clicking a link fetches and renders the target.  Return (values WINDOW FOCUS OPEN).

**`make-editor` (&optional path)**  — Build a text-editor window for PATH (or a scratch buffer).  Return (values WINDOW FOCUS).

**`make-file-dialog` (&key (dir (getcwd)) dirs-only (mode open) (mask *) default-name
  (title
   (case mode
     (save  save file )
     (t
      (if dirs-only
           choose directory
           open file )))))**  — Modal file picker.  MODE :open returns an existing file (or the current directory when DIRS-ONLY); MODE :save returns a name to write, confirming an overwrite.  MASK filters the file list (a glob like "*.lisp"); the Filter/Name field also does type-ahead.  Returns a pathname, or NIL on cancel.

**`make-help` (&optional (topic general))**  — An html-view window showing help TOPIC; topic links navigate within it.

**`make-outline-node` (text &optional (children 'nil) data setter)**  — Construct an OUTLINE-NODE with display TEXT and optional CHILDREN, DATA payload, and DATA SETTER function.

**`make-tpoint` (&optional (x 0) (y 0))**  — Construct a TPOINT at column X and row Y (both default to 0).

**`make-trect` (ax ay bx by)**  — Construct a TRECT from top-left corner (AX,AY) and bottom-right corner (BX,BY).

**`mouse-col` (view e)**

**`mouse-row` (view e)**

**`outline-ensure-children` (n)**  — Lazily populate N's children from its LOADER the first time they are needed. A no-op for ordinary (eager) nodes.  Returns N.

**`outline-node-children` (instance)**  — The list of child OUTLINE-NODEs of node N.

**`outline-node-color` (instance)**  — Optional foreground colour index for node N's row (e.g. a git-status tint), or NIL.

**`outline-node-data` (instance)**  — The arbitrary application payload attached to outline node N.

**`outline-node-expandable-p` (n)**  — True when N can be expanded -- it has children, or a not-yet-loaded LOADER.

**`outline-node-expanded` (instance)**  — True when outline node N is currently expanded (its children shown).

**`outline-node-loader` (instance)**  — Optional thunk (lambda () -> children) called on N's first expand to lazily populate its children, or NIL for an eager node.

**`outline-node-setter` (instance)**  — Optional function (lambda (new-value)) that writes node N's edited DATA back to its source, or NIL.

**`outline-node-text` (instance)**  — The display text of outline node N.

**`ov-current` (ol)**  — The OUTLINE-NODE currently focused, or NIL when the tree is empty.

**`pack-rgb` (r g b)**  — Pack an (R G B) triple (0-255 each) into a 24-bit integer.

**`picture-validator` (template)**  — Match TEMPLATE where # = a digit, A = a letter, and any other char is a literal that must appear verbatim (e.g. "##/##/####").

**`point-equal-p` (a b)**  — True when points A and B have the same X and Y coordinates.

**`point-x` (instance)**  — The column (X) coordinate of point P.

**`point-y` (instance)**  — The row (Y) coordinate of point P.

**`popup-choose` (items &key (title  select ))**  — Modal list picker centred over *ROOT*; return the chosen string or NIL.

**`prompt-string` (title label)**  — Modal one-line prompt; return the entered string, or NIL on cancel.

**`pump-input` (s timeout)**  — Wait up to TIMEOUT seconds for input, decode it, and queue events.  If a mouse button is held with nothing else pending, synthesize ev-mouse-auto. Never blocks while events are already decoded and waiting (so batched/pasted input isn't processed one key per idle-timeout).

**`range-validator` (lo hi)**  — Digits only; the value must parse to an integer in [LO, HI].

**`rect` (x0 y0 x1 y1)**  — Construct a rectangle spanning the half-open range (X0,Y0) inclusive to (X1,Y1) exclusive.

**`rect-assign` (r ax ay bx by)**  — Destructively set rectangle R's corners to (AX,AY)-(BX,BY); return R.

**`rect-ax` (instance)**  — The left edge (X of corner A) of rectangle R, inclusive.

**`rect-ay` (instance)**  — The top edge (Y of corner A) of rectangle R, inclusive.

**`rect-bx` (instance)**  — The right edge (X of corner B) of rectangle R, exclusive.

**`rect-by` (instance)**  — The bottom edge (Y of corner B) of rectangle R, exclusive.

**`rect-contains-p` (r x y)**  — True when point (X,Y) lies within rectangle R (A inclusive, B exclusive).

**`rect-empty-p` (r)**  — True when rectangle R has no area (its A corner meets or crosses its B corner).

**`rect-equal-p` (a b)**  — True when rectangles A and B have identical corner coordinates.

**`rect-grow` (r dx dy)**  — Destructively grow rectangle R by DX columns on each side and DY rows on the top and bottom (negative values shrink it); return R.

**`rect-height` (r)**  — The height of rectangle R (BY - AY).

**`rect-intersect` (r o)**  — Destructively set R to the intersection of R and O.

**`rect-move` (r dx dy)**  — Destructively translate rectangle R by DX columns and DY rows; return R.

**`rect-union` (r o)**  — Destructively set R to the bounding union of R and O.

**`rect-width` (r)**  — The width of rectangle R (BX - AX).

**`register-command` (name action &optional doc (enabled t))**  — Register command NAME (ENABLED may be a boolean or a predicate thunk).  Warns if NAME is redefined from a DIFFERENT source file -- an accidental cross-file collision.  A live redefinition from the same file, or from the REPL (source NIL), is silent, so redefining a command interactively still works.

**`register-menu` (name contributor)**  — Register CONTRIBUTOR -- a function of the desktop returning a menu spec (LABEL item...), or NIL to contribute nothing -- under NAME (a keyword), as a desktop menu-bar contribution. A contribution whose title matches a built-in menu merges into it; otherwise it adds a new top-level menu, positioned by *MENU-ORDER*.  Idempotent: re-registering NAME replaces it, so a file reload doesn't duplicate the menu.  Returns NAME.

**`register-window` (kind builder)**  — Register BUILDER -- a 0-arg function returning (values WINDOW FOCUS OPEN) -- under KIND (a keyword), so the desktop can open it by keyword (from a menu, or when restoring a saved layout).  Idempotent: re-registering KIND REPLACES its builder, so reloading the window's file updates it cleanly.  Returns KIND.

**`revision-log` (fmt &rest args)**  — Record a diagnostic line (wall-clock stamped) in the ring, and append it to *LOG-FILE* when set.  Thread-safe and never signals -- safe from any thread.

**`rgb-attr` (fg-rgb bg-rgb &optional (style 0))**  — Intern a true-colour attribute from 24-bit packed FG-RGB and BG-RGB and an optional STYLE bitmask (+STYLE-BOLD+ etc.); return it.

**`role` (key)**  — The colour attribute the current *THEME* assigns to the semantic role KEY (e.g. :normal, :focused, :status, :frame), or a plain grey-on-black default when the role is unset.

**`run`**  — Phase-7 demo: everything from phases 0-6, plus the session (filter + outline line) restored from ~/.revision-session on start and saved on exit (MOP persistence), and a background thread driving the clock through the worker->UI bridge.

**`run-async` (work &key then on-error (label async))**  — Run WORK (a 0-arg thunk that may block -- a subprocess, a file read, a network fetch) on a fresh background thread so the UI loop stays live; when it returns, run (THEN result) back ON THE UI THREAD (via RUN-ON-UI, which wakes the loop).  A signalled ERROR goes to (ON-ERROR condition) on the UI thread, or is logged under LABEL.  This is the default way a window keeps blocking I/O off the UI thread; only the THEN/ON-ERROR closures touch views, so the single-thread rule holds.  Returns the worker thread.

**`run-desktop`**  — Run the revision IDE: a Turbo-Vision-style desktop with a menu bar, a status bar, and movable / resizable / overlapping windows (drag the title bar, drag the bottom-right corner to resize, click [✕] to close; Window menu tiles/cascades). Returns on File→Exit.

**`run-editor` (&optional path)**  — Run the ported text editor full-screen until Esc.

**`run-html` (&optional (page index))**  — Run the ported HTML browser full-screen until Esc.

**`run-on-ui` (thunk)**  — Run THUNK on the UI thread: immediately if already there, else enqueue it for the event loop to drain.  The single rule that keeps views single-threaded.

**`run-view` (win &key focus open)**  — Run WIN full-screen in its own screen session until it quits.  FOCUS is the initial focused widget; OPEN (a thunk of the screen) may start background work and return a cleanup thunk.

**`save-object` (object path)**  — Serialize OBJECT (via SERIALIZE) and write it readably to PATH, replacing any existing file.  Returns T on success, NIL if the write failed.

**`sb-scroll` (sb delta)**  — Scroll the viewport by DELTA rows (clamped), re-arming follow mode once back at the bottom.

**`sb-set-input` (sb text)**  — Replace the live input with TEXT (caret at end); used for history recall.

**`screen-cell-set` (s x y cell)**  — Set the back-buffer cell at (X,Y).  Coordinates outside the screen are silently ignored, which lets views draw without bounds-checking.

**`screen-height` (instance)**  — The height of screen S in character rows.

**`screen-next-event` (s)**  — Pop the next decoded event, or NIL if none are pending.

**`screen-width` (instance)**  — The width of screen S in character columns.

**`scrollback-append` (sb text)**  — Append TEXT (which may contain newlines and need not end in one) to the transcript, holding any trailing partial line in PENDING for the next chunk.

**`scrollback-clear` (sb)**  — Erase the whole transcript: drop all lines, pending text, presentations and scroll offsets, and re-arm follow mode.

**`scrollback-present` (sb text object)**  — Append TEXT (a full result line, ending in newline) and mark the line(s) it occupies as a presentation of the live OBJECT, so clicking them fires ON-PRESENT.

**`session-file`**  — The pathname of the persisted session file (.revision-session in the user's home).

**`set-cursor-pos` (s x y)**  — Move screen S's hardware cursor to column X, row Y (shown on the next flush).

**`set-cursor-shape` (shape &optional (s *screen*))**  — SHAPE is :block, :underline, or :bar.

**`set-html` (v html)**  — Load HTML string into the html-view V: tokenize, lay out, reset scroll/focus, and repaint.  Returns V.

**`show-cursor` (&optional (s *screen*))**  — Make screen S's hardware cursor visible (rendered on the next flush).

**`string-width` (s &optional (start 0) (end (length s)))**  — Total display width of S[START,END) in terminal columns (per code point; for grapheme-aware width use GRAPHEME-WIDTH over clusters).

**`te-clamp` (te)**  — Clamp the cursor (CY, CX) back into the valid range of the current buffer.

**`te-copy` (te)**  — Copy the current selection to the shared clipboard (no-op when nothing is selected).

**`te-cur` (te)**  — The line string the cursor is currently on.

**`te-cut` (te)**  — Copy the selection to the clipboard and delete it, recording an undo snapshot.

**`te-ensure-visible` (te)**  — Scroll the viewport (vertically and horizontally) so the cursor is on screen, accounting for soft-wrap, the gutter and wide glyphs.

**`te-find` (te query &key (from-line (te-cy te)) (from-col 0))**  — Find QUERY (case-insensitive) at/after (FROM-LINE, FROM-COL); select it and move the cursor to its end.  Return T on a hit.

**`te-find-regex` (te pattern &key (from-line (te-cy te)) (from-col 0))**  — Find the next match of regex PATTERN (per line) from the cursor; select it.

**`te-insert` (te string)**  — Insert STRING at the cursor (replacing any active selection first), recording an undo snapshot; the cursor ends after the inserted text.

**`te-isearch-start` (te)**  — Enter incremental-search mode: keystrokes extend the query and move the match live; Ctrl-S finds the next; Enter accepts; Esc restores the original position.

**`te-load` (te path)**  — Load the file at PATH (UTF-8) into the buffer, set its filename, and clear the modified flag and undo/redo history.  A missing file loads as empty.

**`te-nlines` (te)**  — Number of logical lines in TE's buffer (always at least 1).

**`te-offset` (te line col)**  — Char offset where (LINE,COL) sits in TE's buffer (each newline is one char).

**`te-paste` (te)**  — Insert the clipboard contents at the cursor (replacing any selection).

**`te-pos-at-offset` (te off)**  — (values LINE COL) for char OFFSET in TE's buffer.

**`te-redo!` (te)**  — Redo the most recently undone edit, pushing the current state onto the undo stack.

**`te-replace-all` (te find repl &key regex)**  — Replace every occurrence of FIND with REPL across the buffer (plain substring, or a regex per line when REGEX).  Return the number of replacements.

**`te-save` (te)**  — Write the buffer to its filename (UTF-8) and clear the modified flag.  Return T when saved, NIL when the buffer has no filename.

**`te-save-undo` (te)**  — Push the current buffer state onto the undo stack, clear the redo stack, and mark the buffer modified.  Call before any mutating edit.

**`te-select-all` (te)**  — Select the entire buffer, from the start to the end of the last line.

**`te-selected-string` (te)**  — The currently selected text as a string, or NIL when there is no selection.

**`te-set-text` (te string)**  — Replace the entire buffer with STRING (split on newlines) and reset the cursor, viewport and selection to the top.

**`te-text` (te)**  — The whole buffer as a single string, lines joined by newlines.

**`te-undo!` (te)**  — Undo the most recent edit, pushing the current state onto the redo stack.

**`translate` (tev)**  — Translate a revision event struct into a revision event object, or NIL to ignore.

**`unknown-command-bindings`**  — Command NAMES bound in the reference keymaps that are NOT registered in *COMMANDS* -- i.e. keymap typos.  PERFORM errors on such a name at runtime; the drift/validation test calls this so a typo is caught at build time instead.

**`unregister-window` (kind)**  — Remove KIND's window builder from the registry; returns T when one was registered.

**`view-focused-p` (v)**  — True when V is the focused widget of its root window.

**`view-root` (v)**  — The topmost owner of V (the root window): follow VIEW-OWNER up until it is NIL.

**`window-kinds`**  — The registered window-builder keywords (e.g. for a picker or introspection).

## Variables

**`*after-layout-restore*`**  — A function of no arguments called by RUN-DESKTOP after the saved layout is restored, just before the event loop starts; NIL to do nothing.  An application sets this to run startup code that may inspect or add to the restored windows.  Errors are logged, not fatal.

**`*app-done*`**  — Set by File→Exit to leave the desktop loop.

**`*before-layout-restore*`**  — A function of no arguments called by RUN-DESKTOP after the desktop is built and *DESKTOP* is bound, but before the saved layout is restored; NIL to do nothing.  An application sets this to run early startup code (e.g. load a user config) that should take effect before the previous session's windows reappear.  Errors are logged, not fatal.

**`*context*`**  — The current UI context: the frame-invalidation state (dirty flags + dirty-view set) and the ROOT view the event loop targets.  Dynamic and per-thread; INVALIDATE and every loop operate on it.  Rebind it (see WITH-FRESH-CONTEXT) to run an isolated or embedded UI.

**`*desktop*`**  — The running desktop instance (for cross-window actions like eval-in-REPL).

**`*dialog-keys*`**  — The keymap shared by modal dialogs: Enter runs the ACCEPT command, Esc runs CANCEL.

**`*editor-completions-fn*`**  — Default completion hook (TE TOKEN) -> a list of completion strings for the symbol prefix TOKEN at the cursor; a text-edit's TE-COMPLETER slot overrides it.  (revl wires it to its package-aware completer.)

**`*editor-eval-fn*`**  — Default eval hook (TE) for the editor's Eval chip / context item; a text-edit's TE-EVALUATOR slot overrides it.  (revl wires it to evaluate the selection in the REPL.)

**`*extra-menus*`**  — Alist of NAME (keyword) -> a (DESKTOP) -> menu-spec function.  Managed through REGISTER-MENU; the desktop merges each contribution into its menu bar (see %DESKTOP-MENUS).

**`*global-keys*`**  — The global keymap consulted for every view's keys before its own keymap (quit on q / Esc).

**`*help-pages*`**  — Help topic -> HTML string.

**`*lisp-indenter*`**  — Default indenter hook (TE) -> indent column for a fresh line, used when a text-edit's own TE-INDENTER slot is unset.  An embedding app (e.g. revl) rebinds it to a smarter engine; a Lisp buffer copies it into TE-INDENTER at creation.

**`*log-file*`**  — When set to a pathname, each log line is also appended there.  NIL by default (the in-memory ring is enough for the REPL / LOG-MESSAGES); set it to capture a session's diagnostics to disk.

**`*outline-keys*`**  — The shared keymap for OUTLINE tree widgets: arrow navigation plus expand/collapse.

**`*paren-matcher*`**  — Default bracket-match hook (TEXT OFFSET) -> the matching paren's offset in TEXT, or NIL; a text-edit's TE-PAREN-MATCHER slot overrides it.  (revl wires it to %PAREN-MATCH-OFFSET.)

**`*project-dir*`**  — Default root for file dialogs / new project-manager windows; set by Change-dir.

**`*reference-keymaps*`**  — (SECTION-TITLE . KEYMAP-VAR) pairs for the TOOLKIT's own keymaps.  An application appends its own keymaps (e.g. revl adds Inspector / Project / REPL input / Call-tree). The menu accelerators are added separately, built from the desktop menu tree.

**`*running*`**  — While non-NIL the active event loop keeps running; setting it NIL exits the loop.

**`*screen*`**  — The active terminal screen, or NIL when not initialised.

**`*theme*`**  — Role -> packed attribute.

**`*ui-thread*`**  — The thread running the UI event loop; RUN-ON-UI marshals a closure onto it from worker threads.

**`*url-fetch-fn*`**  — (url) -> HTML string, or NIL.

**`*widget-key-doc*`**  — Extra (SECTION-TITLE . ((KEY-LABEL . DESC) ...)) widget-key groups appended verbatim to the reference, for keys not tied to a toolkit view class (an application may push its own).  The toolkit's own widget keys now come from VIEW-KEY-HINTS via *WIDGET-KEY-VIEWS*.

**`*widget-key-views*`**  — (SECTION-TITLE . VIEW-CLASS) for the widgets whose intrinsic keys -- handled inside HANDLE-EVENT rather than a keymap -- are declared via VIEW-KEY-HINTS.  The reference reads those methods, so each widget's keys are documented once, next to the code that implements them (no separate hand-maintained list to drift).

**`*window-builders*`**  — Alist of KIND (keyword) -> 0-arg builder returning (values WINDOW FOCUS OPEN).  Managed through REGISTER-WINDOW; DT-OPEN and layout save/restore look a builder up by keyword.

## Constants

**`+mb-left+`**  — Button mask bit for the left mouse button.

**`+mb-right+`**  — Button mask bit for the right mouse button.

**`+md-alt+`**  — Modifier bit for the Alt key in an event's modifier mask.

**`+md-ctrl+`**  — Modifier bit for the Ctrl key in an event's modifier mask.

**`+md-shift+`**  — Modifier bit for the Shift key in an event's modifier mask.

## Types

**`attr`**  — A packed colour attribute: an (unsigned-byte 32) encoding foreground, background and style; build with MAKE-ATTR.

