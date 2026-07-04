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
      ((and (characterp ks) (<= 1 (char-code ks) 26))            ; a control char already means Ctrl
       (format nil "Ctrl+~a" (code-char (+ 64 (char-code ks)))))
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
    ("Inspector"      . *inspector-keys*)
    ("Project tree"   . *proj-keys*)
    ("Editor"         . *editor-keys*)
    ("REPL input"     . *repl-input-keys*)
    ("Dialogs"        . *dialog-keys*)
    ("Call-tree"      . *call-tree-keys*))
  "(SECTION-TITLE . KEYMAP-VAR) pairs documented in the reference.  The menu
accelerators are added separately, built from the desktop menu tree.")

(defparameter *widget-key-doc*
  '(("Object lists & tables" .
     (("Alt-I" . "inspect the focused object in the inspector")
      ("Enter" . "activate the focused row (show detail / follow / open)"))))
  "Widget-level keys handled inside the widgets (list-box / table-view) rather than a
keymap -- listed here so the reference stays complete.")

(defun keybinding-reference ()
  "A list of (SECTION-TITLE . ((KEY-LABEL . COMMAND) ...)) covering the menu
accelerators, every named keymap (derived from the live keymaps), and the widget-
level keys in *WIDGET-KEY-DOC*."
  (append
   (list (cons "Menu accelerators"
               (keymap-entries
                (ignore-errors (%menu-accel-keymap (%desktop-menus (make-instance 'desktop)))))))
   (loop for (title . var) in *reference-keymaps*
         when (boundp var)
           collect (cons title (keymap-entries (symbol-value var))))
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

(eval-when (:load-toplevel :execute)
  (export '(key-label keymap-entries keybinding-reference keybinding-markdown keybinding-html)))
