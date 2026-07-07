;;;; reference.lisp --- a keybinding reference DERIVED from the keymaps.
;;;;
;;;; Every binding is a (KEYSYM . MODS) token -> command held in a keymap -- view
;;;; keymaps, the editor keymap, and the menu-accelerator keymap all share this one
;;;; representation.  So the reference is *generated* by walking those keymaps; it is
;;;; never hand-maintained, and a drift test can assert the committed doc matches.

(in-package #:revision)

(defun key-label (token)
  "Human label for a (KEYSYM . MODS) keymap TOKEN, e.g. \"Ctrl+C\", \"Shift+Del\",
\"F2\", \"Alt+X\", \"Up\"."
  (let ((ks (car token)) (m (cdr token)))
    (cond
      ((keywordp ks)
       (let ((base (case ks
                     (:up "Up") (:down "Down") (:left "Left") (:right "Right")
                     (:enter "Enter") (:tab "Tab") (:esc "Esc") (:back "Bksp")
                     (:del "Del") (:ins "Ins") (:home "Home") (:end "End")
                     (:pgup "PgUp") (:pgdn "PgDn") (:space "Space")
                     (t (string-capitalize (symbol-name ks))))))
         (concatenate 'string
                      (if (logtest m +md-ctrl+)  "Ctrl+"  "")
                      (if (logtest m +md-alt+)   "Alt+"   "")
                      (if (logtest m +md-shift+) "Shift+" "")
                      base)))
      (t (accel-label token)))))

(defun %binding-name (v)
  "A human label for a keymap value (a command NAME symbol, or an anonymous command
OBJECT as the menu accelerators hold): the command's :DOC when it has one, else its
name."
  (let ((cmd (cond ((symbolp v) (gethash v *commands*))
                   ((typep v 'command) v))))
    (cond ((and cmd (command-doc cmd)) (command-doc cmd))
          ((symbolp v)                 (string-downcase (symbol-name v)))
          ((typep v 'command)          (princ-to-string (command-name v)))
          (t                           (princ-to-string v)))))

(defun keymap-entries (km)
  "Sorted list of (KEY-LABEL . COMMAND-NAME) for KM's own bindings (not inherited)."
  (let ((out '()))
    (when km
      (maphash (lambda (tok v) (push (cons (key-label tok) (%binding-name v)) out))
               (keymap-bindings km)))
    (sort out (lambda (a b)                       ; by command, then key -- fully deterministic
                (or (string-lessp (cdr a) (cdr b))
                    (and (string-equal (cdr a) (cdr b)) (string-lessp (car a) (car b))))))))

(defparameter *reference-keymaps*
  '(("Global"         . *global-keys*)
    ("Desktop"        . *desktop-keys*)
    ("Outline / tree" . *outline-keys*)
    ("Editor"         . *editor-keys*)
    ("Dialogs"        . *dialog-keys*))
  "(SECTION-TITLE . KEYMAP-VAR) pairs for the TOOLKIT's own keymaps.  An application
appends its own keymaps (e.g. revl adds Inspector / Project / REPL input / Call-tree).
The menu accelerators are added separately, built from the desktop menu tree.")

(defparameter *widget-key-views*
  '(("Input field"           . input-line)
    ("List box"              . list-box)
    ("Radio / check cluster" . cluster)
    ("Table"                 . table-view)
    ("Transcript / REPL log" . scrollback)
    ("HTML / help viewer"    . html-view))
  "(SECTION-TITLE . VIEW-CLASS) for the widgets whose intrinsic keys -- handled inside
HANDLE-EVENT rather than a keymap -- are declared via VIEW-KEY-HINTS.  The reference reads
those methods, so each widget's keys are documented once, next to the code that implements
them (no separate hand-maintained list to drift).")

(defparameter *widget-key-doc* nil
  "Extra (SECTION-TITLE . ((KEY-LABEL . DESC) ...)) widget-key groups appended verbatim to the
reference, for keys not tied to a toolkit view class (an application may push its own).  The
toolkit's own widget keys now come from VIEW-KEY-HINTS via *WIDGET-KEY-VIEWS*.")

(defun %view-key-section (title class)
  "A (TITLE . HINTS) reference section from CLASS's VIEW-KEY-HINTS, or NIL when it declares
none.  Reads the class prototype, so no instance (or its initargs) is needed."
  (let ((c (find-class class nil)))
    (when c
      (ignore-errors (sb-mop:finalize-inheritance c))
      (let ((hints (ignore-errors (view-key-hints (sb-mop:class-prototype c)))))
        (and hints (cons title hints))))))

(defun describe-view-keys (view)
  "Every key VIEW responds to, as (KEY-LABEL . DESCRIPTION): its intrinsic keys (VIEW-KEY-HINTS,
handled inside its own HANDLE-EVENT) followed by the bindings from its keymap chain (each resolved
to its command's doc).  The single place to answer \"what does a key do for this view\" across
BOTH dispatch paths.  Keys it ignores bubble to its owner's keymap -- walk VIEW-OWNER for those."
  (append (view-key-hints view)
          (loop for km = (view-keymap view) then (keymap-parent km)
                while km nconc (keymap-entries km))))

(defun unknown-command-bindings ()
  "Command NAMES bound in the reference keymaps that are NOT registered in *COMMANDS*
-- i.e. keymap typos.  PERFORM errors on such a name at runtime; the drift/validation
test calls this so a typo is caught at build time instead."
  (loop for (nil . var) in *reference-keymaps*
        when (boundp var)
          nconc (let ((bad '()))
                  (maphash (lambda (tok v)
                             (declare (ignore tok))
                             (when (and (symbolp v) v (not (gethash v *commands*)))
                               (pushnew v bad)))
                           (keymap-bindings (symbol-value var)))
                  bad)))

(defun keybinding-reference ()
  "A list of (SECTION-TITLE . ((KEY-LABEL . COMMAND) ...)) covering the menu accelerators,
every named keymap (derived from the live keymaps), each widget's intrinsic keys (from its
VIEW-KEY-HINTS, via *WIDGET-KEY-VIEWS*), and any application extras in *WIDGET-KEY-DOC*."
  (append
   (list (cons "Menu accelerators"
               (keymap-entries
                (ignore-errors (%menu-accel-keymap (%desktop-menus (make-instance 'desktop)))))))
   (loop for (title . var) in *reference-keymaps*
         when (boundp var)
           collect (cons title (keymap-entries (symbol-value var))))
   (loop for (title . cls) in *widget-key-views*      ; widget intrinsic keys, from VIEW-KEY-HINTS
         for sec = (%view-key-section title cls)
         when sec collect sec)
   *widget-key-doc*))

(defun keybinding-markdown (&optional (ref (keybinding-reference)))
  "Render the keybinding reference (see KEYBINDING-REFERENCE) as a Markdown document."
  (with-output-to-string (o)
    (write-string "# revision — keybinding reference" o)
    (format o "~2%_Generated from the keymaps by `revision:keybinding-markdown`. ~
Do not edit by hand — run the generator._~%")
    (dolist (sec ref)
      (when (cdr sec)
        (format o "~%## ~a~2%| Key | Command |~%|-----|---------|~%" (car sec))
        (loop for (key . cmd) in (cdr sec)
              do (format o "| `~a` | `~a` |~%" key cmd))))))

(defun keybinding-html (&optional (ref (keybinding-reference)))
  "Render the keybinding reference (see KEYBINDING-REFERENCE) as HTML for the in-app
help viewer, using the H1/H2/UL/LI/CODE vocabulary the help pages already use."
  (with-output-to-string (o)
    (write-string "<h1>Keybindings</h1>" o)
    (write-string "<p>Generated live from the keymaps, so this is always current.</p>" o)
    (dolist (sec ref)
      (when (cdr sec)
        (format o "<h2>~a</h2><ul>" (car sec))
        (loop for (key . cmd) in (cdr sec)
              do (format o "<li><code>~a</code> — ~a</li>" key cmd))
        (write-string "</ul>" o)))))

;;; (The public API — these reflection symbols included — is exported in one place:
;;; base/package.lisp.)

