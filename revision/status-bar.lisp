;;;; status-bar.lisp --- the desktop's bottom status bar and transient tool notes.
;;;;
;;;; The status bar draws clickable action chips supplied by a PROVIDER thunk, plus
;;;; any transient note (%TOOL-NOTE, set elsewhere) right-aligned so tool feedback is
;;;; visible without raising or refocusing a window.  The *TOOL-MESSAGE* infra and its
;;;; TTL/expiry live here alongside the view that renders them.

(in-package #:revision)

(defvar *tool-message* ""
  "Last transient note (from %TOOL-NOTE); shown right-aligned on the status bar so
tool feedback is visible without raising or refocusing any window.")
(defvar *tool-message-time* 0 "INTERNAL-REAL-TIME when *TOOL-MESSAGE* was last set.")
(defparameter *tool-message-ttl* 4 "Seconds a status-bar note lingers before auto-clearing.")

(defun %expire-tool-message ()
  "Clear the status-bar note once it has been shown for *TOOL-MESSAGE-TTL* seconds.
Returns T when it cleared (so the loop can mark the screen dirty)."
  (when (and (plusp (length *tool-message*))
             (> (- (get-internal-real-time) *tool-message-time*)
                (* *tool-message-ttl* internal-time-units-per-second)))
    (setf *tool-message* "")
    t))

(defun %tool-message-timeout (default)
  "Cap DEFAULT so the idle loop still wakes when a lingering status-bar note is due to
auto-clear (else a note could sit past its TTL until the next input)."
  (if (plusp (length *tool-message*))
      (let ((remaining (- (* *tool-message-ttl* internal-time-units-per-second)
                          (- (get-internal-real-time) *tool-message-time*))))
        (max 0.0 (min default (/ remaining internal-time-units-per-second))))
      default))

(defclass status-bar (view)
  ((provider :initarg :provider :initform nil :accessor stb-provider)  ; thunk -> ((LABEL . THUNK) ...)
   (ranges   :initform '() :accessor stb-ranges))                      ; ((X0 X1 . THUNK) ...) for hit-testing
  (:metaclass reactive-class)
  (:documentation "The desktop's bottom bar: draws clickable action chips supplied by its PROVIDER
thunk, plus any transient tool note right-aligned."))

(defmethod draw ((b status-bar))
  (let* ((attr (role :status)) (w (r-w (view-bounds b)))
         (items (and (stb-provider b) (funcall (stb-provider b))))
         (msg (and (plusp (length *tool-message*)) (format nil " ~a " *tool-message*)))
         (limit (if msg (max 0 (- w (length msg))) w))       ; reserve the right for the note
         (x 0))
    (fill-row b 0 0 w attr)
    (setf (stb-ranges b) '())
    (dolist (it items)
      (let* ((label (format nil " ~a " (car it))) (n (length label)))
        (when (< (+ x n) limit)
          (draw-text b x 0 label attr)
          (push (list x (+ x n) (cdr it)) (stb-ranges b))
          (incf x n)
          (when (< (1+ x) limit) (draw-text b x 0 "│" attr) (incf x 1)))))
    (when msg                                                ; right-aligned transient note, always visible
      (draw-text b (max 0 (- w (length msg))) 0 msg (role :focused)))))

(defmethod handle-event ((b status-bar) (e mouse-down))
  (let ((col (mouse-col b e)))
    (dolist (r (stb-ranges b))
      (when (and (>= col (first r)) (< col (second r))) (funcall (third r)) (return))))
  (setf (handled-p e) t))
