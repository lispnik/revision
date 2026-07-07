;;;; commands.lisp --- keymaps and commands: input bindings and behaviour as data.
;;;;
;;;; Input bindings are *data* (layered, introspectable, rebindable): a KEYMAP
;;;; maps (KEYSYM . MODS) tokens to command names.  Behaviour is an object with a
;;;; reactive ENABLED slot (so disabling one auto-repaints anything that shows
;;;; it), not an integer + a central COND.  Commands are invoked by name through
;;;; PERFORM; keymaps and menus reference them by NAME.

(in-package #:revision)

;;; ---------------------------------------------------------------------------
;;; Keymaps: input bindings are *data* (layered, introspectable, rebindable).
;;; A binding maps a keysym -> a command name (symbol).
;;; ---------------------------------------------------------------------------

(defclass keymap ()
  ((parent   :initarg :parent :initform nil :reader keymap-parent
             :documentation "Fallback keymap consulted when a token is unbound here (the inheritance chain).")
   (bindings :initform (make-hash-table :test 'equal) :reader keymap-bindings))
  (:documentation "A layer of input bindings mapping (KEYSYM . MODS) tokens to command names,
with an optional PARENT for inheritance.  Bindings are data -- introspectable and rebindable."))

;;; A binding key normalises to a (KEYSYM . MODS) token.  Terminals deliver a
;;; Ctrl-letter as a control character (code 1-26) that already carries +md-ctrl+
;;; (see PARSE-PLAIN-BYTE), so fold that in; a (KEYSYM . MODS) cons is taken as-is
;;; and a bare keysym has no modifiers.  This is the SAME token the menu
;;; accelerators use (ACCEL-KEY / ACCEL-MODS), so one representation drives both.
(defun %key-mods (spec)
  (cond ((consp spec) (cdr spec))
        ((and (characterp spec) (<= 1 (char-code spec) 26)) +md-ctrl+)
        (t 0)))
(defun key-token (spec)
  "Canonical (KEYSYM . MODS) for a binding spec (a keysym, a control char, or an
already-formed (KEYSYM . MODS) cons)."
  (cons (if (consp spec) (car spec) spec) (%key-mods spec)))

(defun bind-key (km spec command)
  "Bind SPEC (a keysym, a control char, or a (KEYSYM . MODS) cons) to command name COMMAND
in keymap KM, normalising SPEC to its canonical token first."
  (setf (gethash (key-token spec) (keymap-bindings km)) command))

(defun %km-get (km token)
  (and km (or (gethash token (keymap-bindings km)) (%km-get (keymap-parent km) token))))

(defun keymap-lookup (km keysym &optional (mods 0) loose)
  "Command bound to KEYSYM+MODS in KM's chain.  Exact (keysym . mods) match by default.
With LOOSE true, fall back to a modifier-insensitive (keysym . 0) binding when there is
no exact match -- OFF by default, so a plain binding no longer silently swallows its
modified variants (Ctrl-/Shift-<key> only fires a binding made for it)."
  (or (%km-get km (cons keysym mods))
      (and loose (plusp mods) (%km-get km (cons keysym 0)))))

(defun ctrl (ch)
  "A binding spec for Ctrl-CH: the (KEYSYM . MODS) cons (CH . +md-ctrl+).  Ctrl lives
in the modifier bits -- TRANSLATE normalises the control char terminals send to this
form -- so e.g. (ctrl #\\o) matches the same token the driver produces for Ctrl-O."
  (cons (char-downcase ch) revision::+md-ctrl+))

(defmacro defkeymap (name (&optional parent) &body bindings)
  "Define a keymap NAME (optionally inheriting PARENT) from (KEYSYM COMMAND) pairs."
  `(defparameter ,name
     (let ((km (make-instance 'keymap :parent ,parent)))
       ,@(loop for (k c) in bindings collect `(bind-key km ,k ',c))
       km)))

;;; ---------------------------------------------------------------------------
;;; Commands: behaviour is an object (with a reactive ENABLED slot, so disabling
;;; one auto-repaints anything that shows it), not an integer + a central COND.
;;; ---------------------------------------------------------------------------

(defclass command ()
  ((name    :initarg :name    :reader command-name
            :documentation "The symbol naming this command (its key in *COMMANDS* and in keymaps).")
   (action  :initarg :action  :reader command-action)
   (doc     :initarg :doc     :initform nil :reader command-doc)      ; one-line description (see DEFINE-COMMAND)
   (source  :initarg :source  :initform nil :reader command-source)  ; defining file (cross-file collision detection)
   (enabled :initarg :enabled :initform t   :accessor command-enabled))  ; boolean, or a predicate thunk
  (:metaclass reactive-class)
  (:documentation "A named, reactive unit of behaviour: an ACTION closure over (VIEW EVENT) plus
an ENABLED flag.  Reactive, so toggling ENABLED auto-repaints menus/buttons that show it.
Invoked by name through PERFORM; keymaps and menus reference commands by NAME."))

(defun command-enabled-p (command)
  "Is COMMAND enabled right now?  ENABLED is a boolean, or a predicate thunk evaluated
on demand -- the single enablement check used by PERFORM (and available to menus /
buttons), so a guarded command no longer needs a second, hand-rolled check."
  (let ((e (command-enabled command))) (if (functionp e) (funcall e) e)))

(defvar *commands* (make-hash-table) "Name -> COMMAND object.")

(defun register-command (name action &optional doc (enabled t))
  "Register command NAME (ENABLED may be a boolean or a predicate thunk).  Warns if NAME
is redefined from a DIFFERENT source file -- an accidental cross-file collision.  A live
redefinition from the same file, or from the REPL (source NIL), is silent, so redefining
a command interactively still works."
  (let ((src (or *compile-file-truename* *load-truename*))       ; NIL when evaluated at the REPL
        (old (gethash name *commands*)))
    (when (and old src (command-source old) (not (equal src (command-source old))))
      (warn "revision: command ~s redefined in ~a (first defined in ~a)"
            name (file-namestring src) (file-namestring (command-source old))))
    (setf (gethash name *commands*)
          (make-instance 'command :name name :action action :doc doc :source src :enabled enabled))))

(defmacro define-command (name (view event) &body body)
  "Define and register command NAME with an action over (VIEW EVENT).  A leading
string in BODY (with forms following it) becomes the command's :DOC -- a one-line
description surfaced in the generated keybinding reference."
  (let ((doc (when (and (stringp (first body)) (rest body)) (pop body))))
    `(register-command ',name
                       (lambda (,view ,event) (declare (ignorable ,view ,event)) ,@body)
                       ,doc)))

(defgeneric perform (command view event)
  (:documentation "Run COMMAND (a command object or its name) for VIEW/EVENT.")
  (:method ((c command) view event)
    (when (command-enabled-p c) (funcall (command-action c) view event)))
  (:method ((c symbol) view event)
    (let ((cmd (gethash c *commands*)))
      (if cmd (perform cmd view event)
          (error "PERFORM: no command named ~s -- a keymap or menu binding typo?" c)))))
