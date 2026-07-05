;;;; revision-desktop-tests.lisp --- the desktop shell + plugin registry, headless.
;;;;
;;;; Proves the reusable-toolkit claim without a terminal: a bare `revision' desktop
;;;; hosts a window opened through the *WINDOW-BUILDERS* registry, closes it, merges an
;;;; *EXTRA-MENUS* contribution into the menu bar, and draws with no screen — the plugin
;;;; seam an application (e.g. revl) builds on, exercised on the toolkit alone.
;;;;
;;;; Run from the repo root:  sbcl --script tests/revision-desktop-tests.lisp

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

(defun %make-test-desktop ()
  "A fully-formed desktop laid out to 80x24, no terminal attached."
  (let ((dt (make-instance 'desktop)))
    (setf (dt-menubar dt)  (make-instance 'menu-bar :menus (%desktop-menus dt))
          (dt-statusbar dt) (make-instance 'status-bar :provider (lambda () nil)))
    (layout dt (rect 0 0 80 24))
    dt))

(defun %win-builder (&optional (title " Test "))
  (lambda () (values (make-instance 'window :title title) nil nil)))

;;; 1. the window plugin registry: a self-registered builder opens through DT-OPEN
(let ((*window-builders* (copy-alist *window-builders*)) (*desktop* nil))
  (let ((dt (%make-test-desktop)) (built nil))
    (pushnew (cons :test-win (lambda () (setf built t) (funcall (%win-builder))))
             *window-builders* :key #'car)
    (dt-open dt :test-win)
    (check "dt-open resolves a builder keyword from *window-builders*" built)
    (check "the opened window is hosted and topmost"
           (and (= 1 (length (dt-windows dt))) (eq (dt-top dt) (first (dt-windows dt)))))
    (check "window-kind records the builder keyword (for layout save/restore)"
           (eq :test-win (window-kind (dt-top dt))))
    (dt-close-window dt (dt-top dt))
    (check "dt-close-window removes it from the Z-order" (null (dt-windows dt)))))

;;; 2. a builder FUNCTION opens directly and is NOT persisted (window-kind stays NIL)
(let ((*window-builders* (copy-alist *window-builders*)) (*desktop* nil))
  (let ((dt (%make-test-desktop)))
    (dt-open dt (%win-builder " Fn "))
    (check "dt-open accepts a builder function directly"
           (and (= 1 (length (dt-windows dt))) (null (window-kind (dt-top dt)))))))

;;; 3. two windows: DT-RAISE reorders the Z-order / focus
(let ((*window-builders* (copy-alist *window-builders*)) (*desktop* nil))
  (let ((dt (%make-test-desktop)))
    (dt-open dt (%win-builder " A ")) (dt-open dt (%win-builder " B "))
    (let ((a (first (dt-windows dt))))
      (check "the later window is on top" (string= " B " (window-title (dt-top dt))))
      (dt-raise dt a)
      (check "dt-raise brings a buried window to the top" (eq a (dt-top dt))))))

;;; 4. the *EXTRA-MENUS* contribution seam + same-title merge in %ORDER-MENUS
(let ((*extra-menus* nil) (*desktop* nil))
  (let ((dt (%make-test-desktop)))
    (push (lambda (d) (declare (ignore d)) (list "Tools" (list "Frob" (lambda () nil)))) *extra-menus*)
    (check "an *extra-menus* contribution appears in the menu bar"
           (member "Tools" (mapcar #'car (%desktop-menus dt)) :test #'string=))
    (push (lambda (d) (declare (ignore d)) (list "Help" (list "Extra topic" (lambda () nil)))) *extra-menus*)
    (let ((titles (mapcar #'car (%desktop-menus dt))))
      (check "%order-menus merges a contributed Help into the shell's single Help menu"
             (= 1 (count "Help" titles :test #'string=))))))

;;; 5. drawing a bare desktop (with a window) is safe when no screen is attached
(let ((*screen* nil) (*window-builders* (copy-alist *window-builders*)) (*desktop* nil))
  (let ((dt (%make-test-desktop)))
    (dt-open dt (%win-builder " W "))
    (check "draw is a safe no-op on a headless desktop (no *screen*)"
           (progn (draw dt) t))))

;;; ===========================================================================
(format t "~%~d passed, ~d failed~%" *pass* *fail*)
(sb-ext:exit :code (if (zerop *fail*) 0 1))
