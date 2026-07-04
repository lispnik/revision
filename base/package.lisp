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
      #:*desktop* #:*editor-completions-fn* #:*editor-eval-fn*
   #:*global-keys* #:*help-pages*   #:*lisp-indenter* 
    #:*paren-matcher*    
       #:*screen* #:*theme*
   #:*ui-thread* #:*url-fetch-fn*
    #:+mb-left+ #:+mb-right+ #:+md-alt+ #:+md-ctrl+ #:+md-shift+

        #:add-laid
   #:add-subview #:all-focusables #:attr  #:attr-bg #:attr-fg
   #:attr-rgb-bg #:attr-rgb-fg #:attr-rgb-p #:bind-key  #:button
   #:button-command #:button-label #:char-width  #:cluster #:cluster-items
   #:cluster-value #:command #:command-enabled-p  #:command-name #:container
   #:container-focus #:copy-point #:copy-rect
        #:define-command
   #:defkeymap #:deserialize #:desktop  #:dialog #:dialog-result
   #:digits-validator #:disable-command    #:draw
    #:enable-command   #:event #:event-delta
   #:event-keysym #:event-modifiers #:event-where #:exec-view #:fail-validation #:filter-validator
   #:find-view  #:flush-screen #:focus-next #:focusable-p #:fuzzy-filter
   #:handle-event #:handled-p #:hide-cursor #:html-view
   #:input-caret #:input-history-id #:input-line #:input-on-change #:input-text #:input-validator
   #:invalidate #:key-event #:keymap #:keymap-lookup #:keymap-parent #:layout
   #:lisp-colorize #:list-box #:list-items #:list-on-activate #:list-selected #:load-object
   #:make-attr #:make-color-dialog #:make-doc-browser  #:make-file-dialog #:make-help
    #:make-outline-node
   #:make-tpoint #:make-trect #:menu-bar #:mouse-down #:mouse-event #:outline
   #:outline-ensure-children #:outline-focused #:outline-node #:outline-node-children #:outline-node-color #:outline-node-data
   #:outline-node-expandable-p #:outline-node-expanded #:outline-node-loader #:outline-node-setter #:outline-node-text #:outline-roots
   #:pack-rgb  #:perform #:persistent-class #:picture-validator #:point-equal-p
   #:point-x #:point-y #:range-validator #:reactive-class #:rect #:rect-assign
   #:rect-ax #:rect-ay #:rect-bx #:rect-by #:rect-contains-p #:rect-empty-p
   #:rect-equal-p #:rect-grow #:rect-height #:rect-intersect #:rect-move #:rect-union
   #:rect-width #:register-command
       #:rgb-attr #:role
   #:row #:run   #:run-desktop #:run-editor
   #:run-html  #:run-on-ui
     #:run-view #:save-object #:sb-follow #:sb-on-present
   #:sb-scroll  #:screen-cell-set #:screen-height
   #:screen-width #:scrollback #:scrollback-append #:scrollback-clear #:scrollback-present #:serialize
   #:session #:session-file #:session-filter #:session-line
   #:set-cursor-pos #:set-cursor-shape  #:set-html  #:show-cursor
   #:stack #:static-text #:status-bar #:string-width #:subviews #:table-columns
   #:table-rows #:table-selected #:table-view #:te-colorizer #:te-filename #:te-find
   #:te-find-regex #:te-load #:te-modified #:te-replace-all #:te-save #:te-set-text
   #:te-text #:text-edit  #:tpoint #:trect #:ui
   #:validation-error #:validation-message #:view #:view-bounds #:view-focused-p #:view-keymap
   #:view-name #:view-owner #:view-root #:wheel-event #:window #:window-title
   #:with-screen ))
