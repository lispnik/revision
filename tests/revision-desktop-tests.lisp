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

;;; 6. input decoder: Option/Alt as a Meta prefix (ESC + a CSI/SS3 sequence -> Alt+key),
;;; e.g. macOS terminals send Option-F3 as `ESC ESC O R` or `ESC ESC[13~`.
(flet ((decode1 (chars)
         (let ((buf (map '(simple-array (unsigned-byte 8) (*)) #'char-code
                         (coerce chars 'string))))
           (first (parse-input-buffer buf (length buf))))))
  (let ((ev (decode1 (list #\Escape #\Escape #\O #\R))))              ; Option-F3 (SS3)
    (check "ESC ESC O R decodes to F3" (and ev (= (iev-key-code ev) +kb-f3+)))
    (check "ESC ESC O R carries Alt (-> Alt-F3 closes windows)"
           (and ev (logtest (iev-modifiers ev) +md-alt+))))
  (let ((ev (decode1 (list #\Escape #\Escape #\[ #\1 #\3 #\~))))      ; Option-F3 (CSI)
    (check "ESC ESC[13~ decodes to Alt-F3"
           (and ev (= (iev-key-code ev) +kb-f3+) (logtest (iev-modifiers ev) +md-alt+))))
  (let ((ev (decode1 (list #\Escape #\O #\R))))                       ; plain F3, no Alt
    (check "ESC O R (plain F3) has no Alt modifier"
           (and ev (= (iev-key-code ev) +kb-f3+) (not (logtest (iev-modifiers ev) +md-alt+)))))
  (let ((ev (decode1 (list #\Escape #\Escape #\[ #\B))))              ; Option-Down arrow
    (check "ESC ESC[B decodes to Alt-Down"
           (and ev (= (iev-key-code ev) +kb-down+) (logtest (iev-modifiers ev) +md-alt+)))))

;;; 7. menu access keys: an item's first letter selects it (and invokes when unique).
(let ((items (list (list "New" (lambda () nil)) (list "Open" (lambda () nil)) :--
                   (list "Save" (lambda () nil)) (list "Save as" (lambda () nil)))))
  (check "%menu-mnemonic: a unique letter finds the item and reports it sole"
         (multiple-value-bind (idx sole) (%menu-mnemonic items 0 #\o) (and (eql idx 1) sole)))
  (check "%menu-mnemonic: a colliding letter is not sole (selects, doesn't invoke)"
         (multiple-value-bind (idx sole) (%menu-mnemonic items 0 #\s) (and (eql idx 3) (not sole))))
  (check "%menu-mnemonic: repeating cycles to the next match" (eql (%menu-mnemonic items 3 #\s) 4))
  (check "%menu-mnemonic: cycling wraps around" (eql (%menu-mnemonic items 4 #\s) 3))
  (check "%menu-mnemonic: case-insensitive" (eql (%menu-mnemonic items 0 #\O) 1))
  (check "%menu-mnemonic: no match returns NIL" (null (%menu-mnemonic items 0 #\z))))

;;; 7b. Turbo-Vision ~x~ hotkey markers give an item a non-first-letter access key,
;;; so same-first-letter items (Cascade / Close / Close all) get distinct keys.
(check "item-label strips a ~x~ marker" (string= (item-label (list "C~a~scade" #'identity)) "Cascade"))
(check "item-mnemonic reads the marked letter" (char-equal (item-mnemonic (list "C~a~scade" #'identity)) #\a))
(check "item-mnemonic-pos indexes the marked letter" (= (item-mnemonic-pos (list "C~a~scade" #'identity)) 1))
(check "an unmarked item falls back to its first letter"
       (char-equal (item-mnemonic (list "Close" #'identity)) #\c))
(let ((items (list (list "Close" #'identity) (list "C~a~scade" #'identity) (list "Clos~e~ all" #'identity))))
  (check "markers resolve the C conflict: c->Close, a->Cascade, e->Close all"
         (and (eql (%menu-mnemonic items -1 #\c) 0)
              (eql (%menu-mnemonic items -1 #\a) 1)
              (eql (%menu-mnemonic items -1 #\e) 2))))

;;; ===========================================================================
(format t "~%~d passed, ~d failed~%" *pass* *fail*)
(sb-ext:exit :code (if (zerop *fail*) 0 1))
