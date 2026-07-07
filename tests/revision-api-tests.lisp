;;;; revision-api-tests.lisp --- the public API contract, enforced.
;;;;
;;;; base/package.lisp calls its :export list "the SINGLE source of truth for the
;;;; public API".  This test turns that comment into a checked invariant so the
;;;; contract can't silently rot:
;;;;
;;;;   1. every exported symbol resolves to a real definition (a function, macro,
;;;;      variable, class, condition, type, or constant) -- so a typo or a removed
;;;;      definition that leaves a dangling export fails the build, not a caller;
;;;;   2. no exported symbol is `%'-prefixed -- the `%' convention marks a private
;;;;      helper, so exporting one would blur the very boundary the list defines.
;;;;
;;;; Run from the repo root:  sbcl --script tests/revision-api-tests.lisp

(require :asdf)
(asdf:initialize-source-registry
 (list :source-registry (list :tree (uiop:getcwd)) :inherit-configuration))
(handler-bind ((warning #'muffle-warning)) (asdf:load-system :revision))
(in-package #:revision)

(defvar *pass* 0) (defvar *fail* 0)
(defmacro check (desc form)
  `(handler-case (if ,form (progn (incf *pass*) (format t "  ok   ~a~%" ,desc))
                     (progn (incf *fail*) (format t "  FAIL ~a~%" ,desc)))
     (error (e) (incf *fail*) (format t "  ERR  ~a -- ~a~%" ,desc e))))

;;; A few exported symbols are *view-name tags*, not definitions: applications pass
;;; them to FIND-VIEW to locate a framework-provided subview (e.g. an editor
;;; window's text-edit is named EDIT).  VIEW-NAME= matches names by STRING, so the
;;; tag needn't be bound to anything -- exporting it just publishes a discoverable,
;;; documented name.  These are the *only* legitimately unbound exports.
(defparameter *api-name-tags* '(edit)
  "Exported symbols that name a framework subview (for FIND-VIEW) rather than a definition.")

(defun %defined-p (sym)
  "Does SYM name *anything* the framework defines -- a function/macro/special-form,
a variable/constant, a class/condition, a type specifier, or a documented view-name
tag?  This is the test's notion of an export backed by a real definition."
  (or (member sym *api-name-tags*)
      (fboundp sym)
      (and (fboundp `(setf ,sym)) t)               ; a (SETF x) accessor with no plain reader
      (boundp sym)
      (macro-function sym)
      (special-operator-p sym)
      (find-class sym nil)                          ; a class or condition
      (eq :defined (sb-int:info :type :kind sym)))) ; a DEFTYPE / struct / class type name

(defun %external-symbols (package)
  (let ((acc '()))
    (do-external-symbols (s package) (push s acc))
    (sort acc #'string< :key #'symbol-name)))

(let ((exports (%external-symbols :revision)))
  (format t "~&revision exports ~d public symbols.~%" (length exports))

  ;; 1. no dangling exports -- every public symbol is backed by a definition.
  (let ((dangling (remove-if #'%defined-p exports)))
    (check (format nil "every exported symbol resolves to a definition~@[ (dangling: ~{~a~^ ~})~]"
                   (mapcar (lambda (s) (string-downcase (symbol-name s))) dangling))
           (null dangling)))

  ;; 2. the `%' private convention is not violated by the export list.
  (let ((leaked (remove-if-not (lambda (s) (and (plusp (length (symbol-name s)))
                                                (char= #\% (char (symbol-name s) 0))))
                               exports)))
    (check (format nil "no `%'-private symbol is exported~@[ (leaked: ~{~a~^ ~})~]"
                   (mapcar #'symbol-name leaked))
           (null leaked)))

  ;; 3. spot-check the async trio a custom host loop needs is public together:
  ;;    RUN-ON-UI (post to the UI thread), RUN-ASYNC (off-thread work), and
  ;;    DRAIN-UI-CALLBACKS (pump the queue each frame) -- an incomplete trio is a
  ;;    boundary gap, since a hand-written loop can post work but never run it.
  (dolist (sym '(run-on-ui run-async drain-ui-callbacks))
    (check (format nil "~a is exported (the custom-host-loop async trio)" (string-downcase (symbol-name sym)))
           (eq :external (nth-value 1 (find-symbol (symbol-name sym) :revision))))))

(format t "~%~d passed, ~d failed~%" *pass* *fail*)
(when (plusp *fail*) (sb-ext:exit :code 1))
