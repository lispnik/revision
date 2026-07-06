;;;; package.lisp --- the REVISION package: the framework's single public API.
;;;;
;;;; One package for the whole framework — the foundation (geometry, colours, the
;;;; cell/draw-buffer + Unicode/grapheme engine, events, the screen driver, the
;;;; outline-node struct) in base/, and the CLOS kernel (reactive class, events,
;;;; keymaps/commands, layout, theming, widgets, windows) in revision/.
;;;;
;;;; This :export list is the SINGLE source of truth for the public API — a
;;;; deliberate, grouped contract, not the accidental union of what callers touched.
;;;; The reference in API.md is generated from these symbols' docstrings (`make api`).

(defpackage #:revision
  (:use #:common-lisp)
  (:documentation "A CLOS-native text-mode UI framework for Common Lisp.")
  (:export

   ;; ---- Geometry: points & rectangles ------------------------------------
   #:tpoint #:make-tpoint #:point-x #:point-y #:point-equal-p #:copy-point
   #:trect #:make-trect #:rect #:rect-ax #:rect-ay #:rect-bx #:rect-by
   #:rect-width #:rect-height #:rect-move #:rect-grow #:rect-union #:rect-intersect
   #:rect-contains-p #:rect-empty-p #:rect-equal-p #:rect-assign #:copy-rect

   ;; ---- Colours & display attributes -------------------------------------
   #:attr #:make-attr #:attr-fg #:attr-bg #:attr-rgb-fg #:attr-rgb-bg #:attr-rgb-p
   #:rgb-attr #:pack-rgb #:*theme* #:role
   #:char-width #:string-width                       ; display-column widths (wide CJK / emoji)

   ;; ---- Screen & terminal driver -----------------------------------------
   #:*screen* #:screen #:screen-width #:screen-height #:with-screen
   #:flush-screen #:set-cursor-pos #:set-cursor-shape #:show-cursor #:hide-cursor
   #:screen-cell-set #:screen-next-event #:pump-input          ; low-level: custom host loops

   ;; ---- Events -----------------------------------------------------------
   #:event #:key-event #:mouse-event #:mouse-down #:wheel-event
   #:event-keysym #:event-modifiers #:event-where #:event-delta #:handled-p
   #:+md-ctrl+ #:+md-alt+ #:+md-shift+ #:+mb-left+ #:+mb-right+

   ;; ---- The view protocol & event loop -----------------------------------
   #:view #:container #:handle-event #:draw #:invalidate #:find-view
   #:focus-next #:focusable-p #:all-focusables #:add-subview #:add-laid #:subviews
   #:view-bounds #:view-name #:view-owner #:view-root #:view-keymap #:view-focused-p
   #:container-focus #:run-view #:run-on-ui #:run-async
   #:*running* #:*dirty* #:*root* #:*ui-thread*

   ;; ---- Commands ---------------------------------------------------------
   #:command #:command-name #:command-enabled-p #:define-command #:register-command
   #:perform #:disable-command #:enable-command #:reactive-class

   ;; ---- Keymaps ----------------------------------------------------------
   #:keymap #:keymap-parent #:keymap-lookup #:defkeymap #:bind-key #:ctrl #:translate
   #:*global-keys* #:*outline-keys* #:*dialog-keys*

   ;; ---- Layout (the UI macro + containers) -------------------------------
   #:ui #:layout #:stack #:row

   ;; ---- Widgets ----------------------------------------------------------
   #:static-text #:static-text-text #:label
   #:button #:button-command #:button-label
   #:input-line #:input-text #:input-caret #:input-validator #:input-on-change
   #:input-history-id #:input-notify
   #:list-box #:list-items #:list-selected #:list-top #:list-on-activate #:list-scroll-fix
   #:cluster #:cluster-items #:cluster-value
   #:html-view #:set-html #:*url-fetch-fn*

   ;; ---- Text editor ------------------------------------------------------
   #:text-edit #:editor-window #:make-editor #:edit
   #:te-text #:te-set-text #:te-cx #:te-cy #:te-cur #:te-nlines #:te-offset #:te-pos-at-offset
   #:te-anchor #:te-clamp #:te-ensure-visible #:te-selected-string #:te-select-all
   #:te-insert #:te-copy #:te-cut #:te-paste
   #:te-undo #:te-undo! #:te-redo #:te-redo! #:te-save-undo
   #:te-find #:te-find-regex #:te-replace-all #:te-isearch-start
   #:te-load #:te-save #:te-filename #:te-modified
   #:te-auto-close #:te-line-numbers #:te-notes #:te-colorizer #:lisp-colorize
   #:te-indenter #:te-completer #:te-paren-matcher #:te-evaluator   ; per-editor hook overrides
   #:*lisp-indenter* #:*paren-matcher* #:*editor-eval-fn* #:*editor-completions-fn*

   ;; ---- Scrollback (append-only transcript, e.g. a REPL) -----------------
   #:scrollback #:scrollback-append #:scrollback-present #:scrollback-clear
   #:sb-lines #:sb-top #:sb-follow #:sb-pending #:sb-scroll
   #:sb-input #:sb-iprompt #:sb-icaret #:sb-iactive #:sb-on-submit #:sb-on-present #:sb-set-input

   ;; ---- Table ------------------------------------------------------------
   #:table-view #:table-window #:table-columns #:table-rows #:table-selected
   #:table-top #:table-hleft

   ;; ---- Outline (collapsible tree) + its node model ----------------------
   #:outline #:outline-roots #:outline-focused #:outline-top #:outline-ensure-children #:ov-current
   #:outline-node #:make-outline-node #:outline-node-text #:outline-node-children
   #:outline-node-data #:outline-node-color #:outline-node-expanded #:outline-node-expandable-p
   #:outline-node-loader #:outline-node-setter

   ;; ---- Windows & the desktop shell --------------------------------------
   #:window #:window-title #:window-help #:window-kind #:window-scroll-target
   #:window-dirty-p #:window-esc-dismissable-p        ; close/Esc protocol
   #:window-save-state #:window-restore-state         ; per-window layout persistence
   #:desktop #:menu-bar #:status-bar #:status-hints #:run-desktop
   #:*desktop* #:*app-done* #:*window-builders* #:*extra-menus*
   #:dt-open #:dt-close-window #:dt-top #:dt-windows #:dt-raise #:dt-refocus
   #:dt-save-layout #:dt-load-layout
   #:context-menu #:popup-choose

   ;; ---- Dialogs & prompts ------------------------------------------------
   #:dialog #:dialog-result #:exec-view #:make-color-dialog #:make-file-dialog
   #:prompt-string #:*project-dir*

   ;; ---- Input validators -------------------------------------------------
   #:validation-error #:validation-message #:fail-validation
   #:range-validator #:picture-validator #:digits-validator #:filter-validator

   ;; ---- HTML help viewer -------------------------------------------------
   #:make-help #:make-doc-browser #:*help-pages*

   ;; ---- Persistence (save/restore objects across sessions) ---------------
   #:session #:persistent-class #:load-object #:save-object #:serialize #:deserialize
   #:session-file #:session-filter #:session-line

   ;; ---- Diagnostics: a log for otherwise-swallowed failures --------------
   #:revision-log #:log-messages #:*log-file* #:ignoring-errors

   ;; ---- Text search / fuzzy matching -------------------------------------
   #:fuzzy-filter

   ;; ---- Standalone full-screen runners (host one widget, no desktop) -----
   #:run #:run-editor #:run-html

   ;; ---- Reflection: the keybinding + API references (generated) ----------
   #:keybinding-reference #:keybinding-markdown #:keybinding-html #:keymap-entries
   #:key-label #:unknown-command-bindings #:*reference-keymaps* #:*widget-key-doc*
   #:api-markdown))
