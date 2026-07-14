;;;; view.lisp --- the view hierarchy, containers, focus, and (view x event) dispatch.
;;;;
;;;; A VIEW is a reactive rectangular region that draws itself and handles events;
;;;; CONTAINER extends it with subviews.  HANDLE-EVENT is the core multimethod on
;;;; (view x event): the base view turns a key into a command via its keymap chain
;;;; (see commands.lisp), containers route to their focused leaf and manage
;;;; Tab/Shift-Tab, and mouse events hit-test the tree top-down to the pointer.

(in-package #:revision)

;;; ---------------------------------------------------------------------------
;;; Views.  Bounds reuse revision's TRECT; capabilities would be mixins -- here we
;;; only need the base + OUTLINE.
;;; ---------------------------------------------------------------------------

(defclass view ()
  ((bounds :initarg :bounds :initform nil :accessor view-bounds
           :documentation "The view's screen rectangle (a revision TRECT), assigned by LAYOUT.")
   (owner  :initarg :owner  :initform nil :accessor view-owner
           :documentation "The containing view (NIL for a root window); walk it up via VIEW-ROOT.")
   (name   :initarg :name   :initform nil :accessor view-name
           :documentation "Optional symbol identifying the view, used by FIND-VIEW lookups.")
   (keymap :initarg :keymap :initform nil :accessor view-keymap
           :documentation "The view's KEYMAP (or NIL); its chain turns key events into commands."))
  (:metaclass reactive-class)
  (:documentation "Root of the view hierarchy: a rectangular region that draws itself and
handles events.  A reactive instance, so mutating a slot repaints; subclasses add HANDLE-EVENT
and DRAW methods.  CONTAINER extends it with subviews."))

(defgeneric draw (view)
  (:documentation "Render VIEW into the screen back buffer, within its bounds."))

(defgeneric layout (view rect)
  (:documentation "Assign VIEW (and its subtree) bounds within RECT.")
  (:method ((v view) rect) (setf (view-bounds v) rect)))

;;; geometry shorthands over revision's TRECT
(defun rect (x0 y0 x1 y1)
  "Construct a rectangle spanning the half-open range (X0,Y0) inclusive to (X1,Y1) exclusive."
  (revision::make-trect x0 y0 x1 y1))
(defun r-x0 (r) (revision::rect-ax r))   (defun r-y0 (r) (revision::rect-ay r))
(defun r-x1 (r) (revision::rect-bx r))   (defun r-y1 (r) (revision::rect-by r))
(defun r-w  (r) (revision::rect-width r)) (defun r-h (r) (revision::rect-height r))

;;; ---------------------------------------------------------------------------
;;; Dispatch: handle-event is a multimethod on (view x event).  The base view
;;; turns a key into a command via its keymap chain; everything else is methods.
;;; ---------------------------------------------------------------------------

(defgeneric handle-event (view event)
  (:documentation "Dispatch EVENT to VIEW: the core (view x event) multimethod protocol.  The base
VIEW turns a key event into a command via its keymap chain; subclasses add methods and set
HANDLED-P once they consume it.  The default method ignores the event.")
  (:method ((v view) (e event)) nil))

(defmethod handle-event ((v view) (e key-event))
  (let ((cmd (keymap-lookup (view-keymap v) (event-keysym e) (event-modifiers e))))
    (when cmd (perform cmd v e) (setf (handled-p e) t))))

;;; The other side of dispatch, made introspectable.  A widget handles some keys
;;; INTRINSICALLY in its own HANDLE-EVENT (typing, arrows) and bubbles the rest to
;;; the keymap chain via CALL-NEXT-METHOD.  Those intrinsic keys used to be visible
;;; only by reading the COND clauses; VIEW-KEY-HINTS declares them as data next to
;;; the widget, so the generated keybinding reference stays complete and co-located,
;;; and DESCRIBE-VIEW-KEYS (see reference.lisp) can answer "what does a key do here"
;;; across BOTH paths from one place.
(defgeneric view-key-hints (view)
  (:method (v) (declare (ignore v)) nil)
  (:documentation "The (KEY-LABEL . DESCRIPTION) list of keys VIEW handles INTRINSICALLY -- inside its
own HANDLE-EVENT rather than through a keymap.  Default: none.  A widget specializes this next to
its HANDLE-EVENT, making the widget the single source of truth for its own keys; the keybinding
reference and DESCRIBE-VIEW-KEYS read it."))

;;; ---------------------------------------------------------------------------
;;; Focus + containers.  FOCUSABLE-P is a protocol GF (default NIL); a container
;;; routes key events to its focused child, handles Tab/Shift-Tab itself, and
;;; bubbles anything unhandled to its own keymap via CALL-NEXT-METHOD.
;;; ---------------------------------------------------------------------------

(defgeneric focusable-p (view)
  (:documentation "True if VIEW can hold keyboard focus (a focusable leaf).  Default NIL; interactive
widgets override it, and containers use it to enumerate focus stops.")
  (:method ((v view)) nil))

(defclass container (view)
  ((subviews :initform '() :accessor subviews
             :documentation "Child views in paint order (last paints on top); see ADD-SUBVIEW.")
   (focus    :initform nil :accessor container-focus       ; the focused leaf, anywhere below (root only)
             :documentation "On the root window, the focused focusable leaf anywhere in the subtree (else NIL)."))
  (:documentation "A VIEW that holds SUBVIEWS: it draws each child, routes key events to its focused
leaf, handles Tab/Shift-Tab focus movement, and hit-tests mouse events down the tree.  On the
root window CONTAINER-FOCUS names the focused leaf anywhere in the subtree.")
  (:metaclass reactive-class))

(defun add-subview (c v)
  "Add view V as a child of container C (appended last, so it paints on top) and set V's
owner to C.  Returns V."
  (setf (view-owner v) c
        (subviews c) (append (subviews c) (list v)))
  v)

(defun view-root (v)
  "The topmost owner of V (the root window): follow VIEW-OWNER up until it is NIL."
  (if (view-owner v) (view-root (view-owner v)) v))

(defun view-name= (a b)
  "Compare two view-name designators by NAME, not object identity, so a name interned
in a different package still matches -- e.g. an application's 'EDIT and the framework's
'EDIT name the same view.  (EQL on symbols is package-sensitive, which silently made
FIND-VIEW return NIL across packages; comparing SYMBOL-NAMEs removes that footgun.)"
  (cond ((or (null a) (null b)) nil)
        ((and (typep a '(or symbol string character))
              (typep b '(or symbol string character)))
         (string= (string a) (string b)))
        (t (eql a b))))

(defun find-view (root name)
  "Depth-first search for the subview named NAME, or NIL.  Names match by NAME string
\(see VIEW-NAME=), so a lookup works even when NAME is interned in another package."
  (cond ((view-name= (view-name root) name) root)
        ((typep root 'container) (some (lambda (sv) (find-view sv name)) (subviews root)))
        (t nil)))

(defun view-focused-p (v)
  "True when V is the focused widget of its root window."
  (let ((r (view-root v))) (and (typep r 'container) (eq v (container-focus r)))))

;;; Focus is a *window-level* property over every focusable leaf in the subtree,
;;; so nested layout containers don't each need their own focus management.
(defun all-focusables (v)
  "List every focusable leaf in V's subtree, in depth-first paint order -- the window's
Tab order.  Flattens nested layout containers so focus is a window-level property."
  (cond ((focusable-p v) (list v))
        ((typep v 'container) (mapcan #'all-focusables (subviews v)))
        (t nil)))

(defun focus-next (root &optional (dir 1))
  "Move ROOT's focus to the next focusable leaf, cycling; DIR 1 advances (Tab), -1 goes
back (Shift-Tab).  No-op when there are no focusable leaves."
  (let ((fs (all-focusables root)))
    (when fs
      (let ((cur (or (position (container-focus root) fs) 0)))
        (setf (container-focus root) (nth (mod (+ cur dir) (length fs)) fs))))))

(defmethod draw ((c container))
  (dolist (sv (subviews c)) (draw sv)))

(defmethod handle-event ((c container) (e key-event))
  (let ((ks (event-keysym e)))
    (cond
      ((and (logtest (event-modifiers e) revision::+md-alt+) (characterp ks)   ; Alt-<label mnemonic>
            (%dispatch-label-hotkey c ks))
       (setf (handled-p e) t))
      ((eql ks :tab)       (focus-next c 1)  (setf (handled-p e) t))
      ((eql ks :shift-tab) (focus-next c -1) (setf (handled-p e) t))
      (t (let ((f (container-focus c))) (when f (handle-event f e)))   ; -> the focused leaf
         (unless (handled-p e) (call-next-method))))))                 ; -> container's keymap

;;; ---------------------------------------------------------------------------
;;; Mouse: events carry a screen point; dispatch hit-tests the view tree top-down
;;; to the deepest view under the pointer, and a click also focuses it.
;;; ---------------------------------------------------------------------------

(defun point-in-rect-p (x y r)
  (and r (<= (revision::rect-ax r) x) (< x (revision::rect-bx r))
       (<= (revision::rect-ay r) y) (< y (revision::rect-by r))))

(defun view-at (root x y)
  "The deepest view in ROOT's subtree whose bounds contain (X,Y), or NIL.
Children are tested front-to-back (last added paints on top)."
  (when (point-in-rect-p x y (view-bounds root))
    (or (and (typep root 'container)
             (loop for sv in (reverse (subviews root))
                   for hit = (view-at sv x y) when hit return hit))
        root)))

(defun mouse-col (view e) (- (car (event-where e)) (revision::rect-ax (view-bounds view))))
(defun mouse-row (view e) (- (cdr (event-where e)) (revision::rect-ay (view-bounds view))))

(defmethod handle-event ((c container) (e paste-event))         ; route a paste to the focused leaf
  (let ((f (container-focus c))) (when f (handle-event f e))))

(defmethod handle-event ((v view) (e mouse-event)) nil)         ; default: ignore

(defmethod handle-event ((c container) (e mouse-event))
  (let* ((w (event-where e)) (hit (and w (view-at c (car w) (cdr w)))))
    (when (and hit (not (eq hit c)))
      (when (and (typep e 'mouse-down) (focusable-p hit))
        (setf (container-focus (view-root hit)) hit))             ; click focuses
      (handle-event hit e))))
