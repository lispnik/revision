;;;; reactive.lisp --- the reactive metaclass and screen-invalidation state.
;;;;
;;;; Mutating any slot of a reactive instance invalidates the screen, so views
;;;; never call DRAW on themselves -- the loop commits one frame per iteration.
;;;; An :AROUND method on (SETF SLOT-VALUE-USING-CLASS) invalidates only on a
;;;; *changed* value (writing a slot back to its current EQL value is a no-op, so
;;;; per-frame bookkeeping like WINDOW-ACTIVE doesn't perpetually re-dirty the
;;;; screen), and records WHICH view changed so the loop can repaint just the
;;;; affected top window (INVALIDATE / *DIRTY-VIEWS*) instead of the whole desktop.

(in-package #:revision)

(defclass reactive-class (standard-class) ()
  (:documentation "Metaclass whose instances invalidate the screen when a slot write CHANGES
its value: an :around method on (SETF SLOT-VALUE-USING-CLASS) calls INVALIDATE, so views
never repaint themselves -- mutating reactive state schedules one committed frame on the
next loop, and a no-op write (same EQL value) schedules nothing."))
(defmethod sb-mop:validate-superclass ((c reactive-class) (s standard-class)) t)

;;; The frame-invalidation state a running UI reads each loop iteration, bundled as
;;; one first-class CONTEXT rather than a handful of loose globals.  It is bound
;;; per-thread as *CONTEXT* (dynamic, so each thread and each WITH-FRESH-CONTEXT
;;; gets its own), which is what lets an embedded or test UI run without dirtying
;;; the ambient app's state -- INVALIDATE and every event loop operate on *CONTEXT*.
(defstruct (context (:copier nil))
  "One running UI instance's frame state: the invalidation flags the event loop consults
each iteration plus the ROOT view (the modal background) they target.  Bound as *CONTEXT*;
create a fresh one with WITH-FRESH-CONTEXT to isolate an embedded or headless UI."
  (dirty       nil :type boolean)     ; reactive state changed since the last committed frame
  (dirty-views '())                   ; views invalidated since the last frame (for a partial repaint)
  (full-redraw t   :type boolean)     ; force a whole-tree repaint next frame (see the partial-frame path)
  (root        nil))                  ; the current top-level window (the modal background)

(defvar *context* (make-context)
  "The current UI context: the frame-invalidation state (dirty flags + dirty-view set) and
the ROOT view the event loop targets.  Dynamic and per-thread; INVALIDATE and every loop
operate on it.  Rebind it (see WITH-FRESH-CONTEXT) to run an isolated or embedded UI.")

(defmacro with-fresh-context ((&key root) &body body)
  "Run BODY on a fresh, isolated UI context (its own dirty flags, dirty-view set, and ROOT).
INVALIDATE and any event loop inside BODY see only this context, so an embedded, headless,
or under-test UI never dirties -- or is dirtied by -- the ambient application's context."
  `(let ((*context* (make-context :root ,root))) ,@body))

(defun invalidate (&optional object slot)
  "Mark the current context (*CONTEXT*) dirty so its event loop commits a fresh frame next
iteration.  When OBJECT is a VIEW whose geometry did not change, record it for a partial
repaint (only the affected top window is redrawn); anything else -- a non-view, or a BOUNDS
change that can vacate cells -- forces a full-screen redraw.  SLOT is the changed slot's name
(NIL from explicit callers, which are treated as a localizable view change)."
  (let ((c *context*))
    (setf (context-dirty c) t)
    (cond ((not (typep object 'view)) (setf (context-full-redraw c) t))
          ((eq slot 'bounds)          (setf (context-full-redraw c) t))
          (t (pushnew object (context-dirty-views c) :test #'eq)))))

(defmethod (setf sb-mop:slot-value-using-class) :around
    (new (class reactive-class) object slot)
  (let* ((bound (sb-mop:slot-boundp-using-class class object slot))
         (old   (and bound (sb-mop:slot-value-using-class class object slot))))
    (prog1 (call-next-method)
      (unless (and bound (eql old new))        ; a no-op write (same value) schedules no frame
        (invalidate object (sb-mop:slot-definition-name slot))))))
