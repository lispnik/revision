;;;; package.lisp --- the REVISION package (the whole framework's namespace).
;;;;
;;;; One package for the framework: the foundation (geometry, colours, the
;;;; cell/draw-buffer + Unicode/grapheme engine, events, the screen driver, the
;;;; outline-node struct) defined in base/, and the CLOS kernel (reactive class,
;;;; events, keymaps/commands, layout, theming, widgets, windows) in revision/.

(defpackage #:revision
  (:use #:common-lisp)
  (:documentation "A CLOS-native text-mode UI framework for Common Lisp.")
  (:export
   #:*app-windows* #:*color-mode* #:*command-set-changed* #:*desktop* #:*editor-completions-fn* #:*editor-eval-fn* 
   #:*global-keys* #:*help-pages* #:*hyperspec-url-fn* #:*input-multiplexer* #:*lisp-indenter* #:*object->outline-fn* 
   #:*paredit-fn* #:*paren-matcher* #:*profile-fn* #:*project-grep-fn* #:*project-status-fn* #:*reorder-fn* 
   #:*repl-completions-fn* #:*repl-eval-fn* #:*repl-time* #:*rgb-theme* #:*screen* #:*theme* 
   #:*ui-thread* #:*url-fetch-fn* #:+cm-cancel+ #:+cm-close+ #:+cm-command-set-changed+ #:+cm-copy+ 
   #:+cm-cut+ #:+cm-default+ #:+cm-menu+ #:+cm-next+ #:+cm-no+ #:+cm-ok+ 
   #:+cm-paste+ #:+cm-prev+ #:+cm-quit+ #:+cm-receivedfocus+ #:+cm-released+ #:+cm-resize+ 
   #:+cm-valid+ #:+cm-yes+ #:+cm-zoom+ #:+ev-broadcast+ #:+ev-command+ #:+ev-key-down+ 
   #:+ev-keyboard+ #:+ev-message+ #:+ev-mouse-auto+ #:+ev-mouse-down+ #:+ev-mouse-move+ #:+ev-mouse-up+ 
   #:+ev-mouse-wheel+ #:+ev-mouse+ #:+ev-nothing+ #:+kb-alt-x+ #:+kb-back+ #:+kb-ctrl-w+ 
   #:+kb-del+ #:+kb-down+ #:+kb-end+ #:+kb-enter+ #:+kb-esc+ #:+kb-f1+ 
   #:+kb-f10+ #:+kb-f2+ #:+kb-f3+ #:+kb-f4+ #:+kb-f5+ #:+kb-f6+ 
   #:+kb-f7+ #:+kb-f8+ #:+kb-f9+ #:+kb-home+ #:+kb-ins+ #:+kb-left+ 
   #:+kb-pgdn+ #:+kb-pgup+ #:+kb-right+ #:+kb-shift-tab+ #:+kb-space+ #:+kb-tab+ 
   #:+kb-up+ #:+mb-left+ #:+mb-right+ #:+md-alt+ #:+md-ctrl+ #:+md-shift+ 
   #:+mw-down+ #:+mw-up+ #:+theme-amber+ #:+theme-green+ #:+theme-modern+ #:+theme-vga+ 
   #:+wf-close+ #:+wf-grow+ #:+wf-move+ #:+wf-zoom+ #:+wn-no-number+ #:add-laid 
   #:add-subview #:all-focusables #:attr #:attr->ansi #:attr-bg #:attr-fg 
   #:attr-rgb-bg #:attr-rgb-fg #:attr-rgb-p #:bind-key #:broadcast-event #:button 
   #:button-command #:button-label #:char-width #:clear-event #:cluster #:cluster-items 
   #:cluster-value #:command #:command-enabled-p #:command-event #:command-name #:container 
   #:container-focus #:copy-point #:copy-rect #:db-fill #:db-move-buf #:db-move-char 
   #:db-move-cstr #:db-move-str #:db-put-attribute #:db-put-char #:db-width #:define-command 
   #:defkeymap #:deserialize #:desktop #:detect-color-mode #:dialog #:dialog-result 
   #:digits-validator #:disable-command #:disable-commands #:done-screen #:drain-ui-callbacks #:draw 
   #:draw-buffer #:enable-command #:enable-commands #:ensure-repl #:event #:event-delta 
   #:event-keysym #:event-modifiers #:event-where #:exec-view #:fail-validation #:filter-validator 
   #:find-view #:flex-score #:flush-screen #:focus-next #:focusable-p #:fuzzy-filter 
   #:handle-event #:handled-p #:hide-cursor #:html-view #:idle-event #:init-screen 
   #:input-caret #:input-history-id #:input-line #:input-on-change #:input-text #:input-validator 
   #:invalidate #:key-event #:keymap #:keymap-lookup #:keymap-parent #:layout 
   #:lisp-colorize #:list-box #:list-items #:list-on-activate #:list-selected #:load-object 
   #:make-attr #:make-color-dialog #:make-doc-browser #:make-draw-buffer #:make-file-dialog #:make-help 
   #:make-inspector #:make-outline-node #:make-palette #:make-rgb #:make-rgb-theme #:make-table-window 
   #:make-tpoint #:make-trect #:menu-bar #:mouse-down #:mouse-event #:outline 
   #:outline-ensure-children #:outline-focused #:outline-node #:outline-node-children #:outline-node-color #:outline-node-data 
   #:outline-node-expandable-p #:outline-node-expanded #:outline-node-loader #:outline-node-setter #:outline-node-text #:outline-roots 
   #:pack-rgb #:palette-ref #:perform #:persistent-class #:picture-validator #:point-equal-p 
   #:point-x #:point-y #:range-validator #:reactive-class #:rect #:rect-assign 
   #:rect-ax #:rect-ay #:rect-bx #:rect-by #:rect-contains-p #:rect-empty-p 
   #:rect-equal-p #:rect-grow #:rect-height #:rect-intersect #:rect-move #:rect-union 
   #:rect-width #:register-command #:repl-busy #:repl-hist-vars #:repl-last-value #:repl-last-value-p 
   #:repl-package #:repl-submit-string #:repl-window #:reset-commands #:rgb-attr #:role 
   #:row #:run #:run-app #:run-browser #:run-desktop #:run-editor 
   #:run-html #:run-menu #:run-on-ui #:run-packages #:run-project #:run-repl 
   #:run-systems #:run-threadmon #:run-view #:save-object #:sb-follow #:sb-on-present 
   #:sb-scroll #:screen-back-buffer #:screen-cell-set #:screen-height #:screen-invalidate #:screen-resize 
   #:screen-width #:scrollback #:scrollback-append #:scrollback-clear #:scrollback-present #:serialize 
   #:session #:session-file #:session-filter #:session-line #:set-color-theme #:set-command-enabled 
   #:set-cursor-pos #:set-cursor-shape #:set-double-click-time #:set-html #:set-mouse-cursor #:show-cursor 
   #:stack #:static-text #:status-bar #:string-width #:subviews #:table-columns 
   #:table-rows #:table-selected #:table-view #:te-colorizer #:te-filename #:te-find 
   #:te-find-regex #:te-load #:te-modified #:te-replace-all #:te-save #:te-set-text 
   #:te-text #:text-edit #:tpalette #:tpoint #:trect #:ui 
   #:validation-error #:validation-message #:view #:view-bounds #:view-focused-p #:view-keymap 
   #:view-name #:view-owner #:view-root #:wheel-event #:window #:window-title 
   #:with-screen ))
