;;;; runtime.lisp --- three non-UI services:
;;;;   (1) a diagnostic log + IGNORING-ERRORS, so a swallowed failure on the
;;;;       persistence/desktop paths is recorded instead of vanishing;
;;;;   (2) MOP-based persistence: serialize a model by introspecting its slots,
;;;;       skipping ones marked :transient -- no hand-written streamers;
;;;;   (3) a worker->UI bridge: background threads post closures with RUN-ON-UI
;;;;       (and RUN-ASYNC runs blocking I/O off the UI thread), and the event loop
;;;;       runs them on the UI thread via DRAIN-UI-CALLBACKS.

(in-package #:revision)

;;; ===========================================================================
;;; Diagnostic log.  A TUI owns the terminal, so it can't scribble errors to
;;; stdout/stderr without corrupting the screen; instead swallowed failures go to
;;; an in-memory ring (and an optional file).  IGNORING-ERRORS is IGNORE-ERRORS
;;; that logs first -- used where a silent DROP hides bugs (session restore, layout
;;; save/load, background callbacks) rather than where failure is expected (parsing).
;;; ===========================================================================

(defparameter *log-capacity* 200 "How many recent log lines the ring buffer keeps.")
(defvar *log-ring* (make-array *log-capacity* :initial-element nil))
(defvar *log-count* 0 "Total lines ever logged (indexes into the ring modulo its size).")
(defvar *log-lock* (sb-thread:make-mutex :name "revision-log"))
(defvar *log-file* nil
  "When set to a pathname, each log line is also appended there.  NIL by default
\(the in-memory ring is enough for the REPL / LOG-MESSAGES); set it to capture a
session's diagnostics to disk.")

(defun revision-log (fmt &rest args)
  "Record a diagnostic line (wall-clock stamped) in the ring, and append it to
*LOG-FILE* when set.  Thread-safe and never signals -- safe from any thread."
  (ignore-errors
    (let ((line (multiple-value-bind (s m h) (decode-universal-time (get-universal-time))
                  (format nil "~2,'0d:~2,'0d:~2,'0d ~a" h m s (apply #'format nil fmt args)))))
      (sb-thread:with-mutex (*log-lock*)
        (setf (aref *log-ring* (mod *log-count* *log-capacity*)) line)
        (incf *log-count*)
        (when *log-file*
          (with-open-file (s *log-file* :direction :output
                                        :if-exists :append :if-does-not-exist :create)
            (write-line line s))))
      line)))

(defun log-messages ()
  "The recent diagnostic lines (oldest first) from the in-memory ring."
  (sb-thread:with-mutex (*log-lock*)
    (loop for i from (max 0 (- *log-count* *log-capacity*)) below *log-count*
          collect (aref *log-ring* (mod i *log-capacity*)))))

(defmacro ignoring-errors ((context) &body body)
  "Evaluate BODY like IGNORE-ERRORS -- returning NIL on any ERROR instead of
propagating -- but first REVISION-LOG the condition under CONTEXT (a short string),
so a swallowed failure on a persistence/desktop path stays diagnosable."
  (let ((e (gensym "E")))
    `(handler-case (progn ,@body)
       (error (,e) (revision-log "~a: ~a" ,context ,e) nil))))

;;; ===========================================================================
;;; Persistence via the metaobject protocol
;;; ===========================================================================

(defclass persistent-class (standard-class) ()
  (:documentation "Metaclass for objects whose marked slots are saved and restored across sessions; see SAVE-OBJECT / LOAD-OBJECT."))
(defmethod sb-mop:validate-superclass ((c persistent-class) (s standard-class)) t)

(defclass persistent-slot-mixin ()
  ((transient :initarg :transient :initform nil :reader slot-transient-p)))
(defclass persistent-direct-slot (persistent-slot-mixin sb-mop:standard-direct-slot-definition) ())
(defclass persistent-effective-slot (persistent-slot-mixin sb-mop:standard-effective-slot-definition) ())

(defmethod sb-mop:direct-slot-definition-class ((c persistent-class) &rest initargs)
  (declare (ignore initargs)) (find-class 'persistent-direct-slot))
(defmethod sb-mop:effective-slot-definition-class ((c persistent-class) &rest initargs)
  (declare (ignore initargs)) (find-class 'persistent-effective-slot))
(defmethod sb-mop:compute-effective-slot-definition ((c persistent-class) name dslots)
  (declare (ignore name))
  (let ((eslot (call-next-method)))
    (setf (slot-value eslot 'transient) (some #'slot-transient-p dslots))
    eslot))

(defgeneric serialize (object)
  (:documentation "A readable representation of OBJECT.  Persistent-class objects
become (:object CLASS slot val ...) over their non-transient, bound slots.")
  (:method ((x t)) x)                                   ; numbers, strings, symbols, t, nil
  (:method ((x cons)) (cons (serialize (car x)) (serialize (cdr x))))
  (:method ((obj standard-object))
    (let ((class (class-of obj)))
      (if (typep class 'persistent-class)
          (list* :object (class-name class)
                 (loop for slot in (sb-mop:class-slots class)
                       for name = (sb-mop:slot-definition-name slot)
                       unless (or (slot-transient-p slot) (not (slot-boundp obj name)))
                         append (list name (serialize (slot-value obj name)))))
          obj))))

(defun deserialize (form)
  "Reconstruct what SERIALIZE produced."
  (cond
    ((and (consp form) (eq (car form) :object))
     (let ((obj (make-instance (second form))))
       (loop for (name val) on (cddr form) by #'cddr
             do (setf (slot-value obj name) (deserialize val)))
       obj))
    ((consp form) (cons (deserialize (car form)) (deserialize (cdr form))))
    (t form)))

(defun save-object (object path)
  "Serialize OBJECT (via SERIALIZE) and write it readably to PATH, replacing any
existing file.  Returns T on success, NIL if the write failed."
  (ignoring-errors ("save-object")
   (with-open-file (s path :direction :output :if-exists :supersede :if-does-not-exist :create)
     (let ((*print-readably* nil)) (prin1 (serialize object) s)))
   t))

(defun load-object (path)
  "Read and DESERIALIZE the object previously written to PATH by SAVE-OBJECT.
Returns the reconstructed object, or NIL if PATH is missing or unreadable."
  (when (probe-file path)
    (ignoring-errors ("load-object")
      (with-open-file (s path) (deserialize (read s nil nil))))))

;;; A small persisted model for the demo: the filter text and outline line are
;;; saved; TOUCHED is :transient (recomputed each run, never written).
(defclass session ()
  ((filter  :initarg :filter :initform "" :accessor session-filter
            :documentation "The saved filter/type-ahead text, persisted across runs.")
   (line    :initarg :line   :initform 1  :accessor session-line
            :documentation "The saved outline line/cursor position, persisted across runs.")
   (touched :initform 0 :accessor session-touched :transient t))
  (:metaclass persistent-class)
  (:documentation "A small persisted model: the FILTER text and outline LINE are written to disk and
restored on the next run.  TOUCHED is :transient — recomputed each run, never saved."))

(defun session-file ()
  "The pathname of the persisted session file (.revision-session in the user's home)."
  (merge-pathnames ".revision-session" (user-homedir-pathname)))

;;; ===========================================================================
;;; Worker -> UI bridge
;;; ===========================================================================

(defvar *ui-thread* nil
  "The thread running the UI event loop; RUN-ON-UI marshals a closure onto it from worker threads.")
(defvar *ui-lock* (sb-thread:make-mutex :name "revision-ui-queue"))
(defvar *ui-queue* '())   ; FIFO list of thunks awaiting the UI thread

(defun ui-thread-p () (or (null *ui-thread*) (eq sb-thread:*current-thread* *ui-thread*)))

(defun run-on-ui (thunk)
  "Run THUNK on the UI thread: immediately if already there, else enqueue it for
the event loop to drain.  The single rule that keeps views single-threaded."
  (if (ui-thread-p)
      (funcall thunk)
      (progn
        (sb-thread:with-mutex (*ui-lock*) (setf *ui-queue* (append *ui-queue* (list thunk))))
        (wake-ui))))                       ; break the loop's idle SELECT so the callback drains now

(defun drain-ui-callbacks ()
  "Run (on the UI thread) every thunk posted since the last drain."
  (let ((thunks (sb-thread:with-mutex (*ui-lock*) (prog1 *ui-queue* (setf *ui-queue* '())))))
    (dolist (th thunks) (ignoring-errors ("ui-callback") (funcall th)))))

(defun run-async (work &key then on-error (label "async"))
  "Run WORK (a 0-arg thunk that may block -- a subprocess, a file read, a network
fetch) on a fresh background thread so the UI loop stays live; when it returns, run
(THEN result) back ON THE UI THREAD (via RUN-ON-UI, which wakes the loop).  A signalled
ERROR goes to (ON-ERROR condition) on the UI thread, or is logged under LABEL.  This is
the default way a window keeps blocking I/O off the UI thread; only the THEN/ON-ERROR
closures touch views, so the single-thread rule holds.  Returns the worker thread."
  (sb-thread:make-thread
   (lambda ()
     (handler-case
         (let ((result (funcall work)))
           (run-on-ui (lambda () (when then (funcall then result)))))
       (error (e)
         (run-on-ui (lambda ()
                      (if on-error (funcall on-error e)
                          (revision-log "~a: ~a" label e)))))))
   :name (format nil "revision-~a" label)))
