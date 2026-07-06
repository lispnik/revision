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

;;; SERIALIZE walks OBJECT into a form the Lisp reader can read back.  It handles the
;;; readable atoms (numbers, strings, symbols, characters, pathnames), the aggregate
;;; containers (cons, vector, array, hash-table -- recursed, not left as unreadable
;;; #<...> text), and persistent-class objects.  Two deliberate guarantees:
;;;   * a CYCLE signals (a bounded, logged error) instead of recursing forever;
;;;   * an unserializable value (a function, a stream, a plain CLOS object) SIGNALS
;;;     rather than being written as text that won't read back -- fail loud, not silent.
;;; Shared (non-cyclic) structure is NOT preserved: a value reachable by two paths is
;;; written twice, so it deserializes to two EQUAL-but-not-EQ copies.  The reserved
;;; head markers are :object :vector :array :hash -- a list starting with one of those
;;; is interpreted as an encoding, so plain data must not begin with them.

(defvar *serialize-seen* nil
  "Set of aggregates on the current SERIALIZE recursion path (for cycle detection).")

(defmethod serialize :around ((x t))
  "Establish the cycle-detection table once, at the outermost SERIALIZE call."
  (if *serialize-seen* (call-next-method)
      (let ((*serialize-seen* (make-hash-table :test 'eq))) (call-next-method))))

(defun %ser-agg (x body-fn)
  "Run BODY-FN to serialize aggregate X, guarding against a cycle back through X."
  (when (gethash x *serialize-seen*)
    (error "SERIALIZE: circular structure through a ~a -- cannot persist it" (type-of x)))
  (setf (gethash x *serialize-seen*) t)
  (unwind-protect (funcall body-fn) (remhash x *serialize-seen*)))

(defgeneric serialize (object)
  (:documentation "A readable representation of OBJECT (see the notes above): readable atoms
pass through, cons/vector/array/hash-table recurse, and persistent-class objects become
(:object CLASS slot val ...) over their non-transient, bound slots.  Cycles and
unserializable values SIGNAL.  Extend it with methods for an application's own types.")
  ;; readable atoms -- pass through (STRING is a VECTOR, so it needs its own method
  ;; to win over the VECTOR method below)
  (:method ((x number))    x)
  (:method ((x symbol))    x)                          ; nil, t, keywords
  (:method ((x string))    x)
  (:method ((x character)) x)
  (:method ((x pathname))  x)
  (:method ((x cons))
    (%ser-agg x (lambda () (cons (serialize (car x)) (serialize (cdr x))))))
  (:method ((x vector))                                ; non-string vectors
    (%ser-agg x (lambda () (list* :vector (map 'list #'serialize x)))))
  (:method ((x array))                                 ; rank >= 2 (VECTOR is more specific)
    (%ser-agg x (lambda () (list :array (array-dimensions x)
                                 (loop for i below (array-total-size x)
                                       collect (serialize (row-major-aref x i)))))))
  (:method ((x hash-table))
    (%ser-agg x (lambda () (list* :hash (hash-table-test x)
                                  (loop for k being the hash-keys of x using (hash-value v)
                                        collect (serialize k) collect (serialize v))))))
  (:method ((obj standard-object))
    (let ((class (class-of obj)))
      (unless (typep class 'persistent-class)
        (error "SERIALIZE: ~s is a plain ~a, not a persistent-class instance -- mark the ~
                owning slot :transient or add a SERIALIZE method for its type"
               obj (class-name class)))
      (%ser-agg obj
                (lambda ()
                  (list* :object (class-name class)
                         (loop for slot in (sb-mop:class-slots class)
                               for name = (sb-mop:slot-definition-name slot)
                               unless (or (slot-transient-p slot) (not (slot-boundp obj name)))
                                 append (list name (serialize (slot-value obj name)))))))))
  (:method ((x t))
    (error "SERIALIZE: cannot serialize ~s (a ~a) -- mark the owning slot :transient, ~
            or add a SERIALIZE/DESERIALIZE method for its type" x (type-of x))))

(defun deserialize (form)
  "Reconstruct what SERIALIZE produced (SERIALIZE guarantees acyclic output, so this
never needs cycle handling)."
  (cond
    ((atom form) form)
    ((eq (car form) :object)
     (let ((obj (make-instance (second form))))
       (loop for (name val) on (cddr form) by #'cddr
             do (setf (slot-value obj name) (deserialize val)))
       obj))
    ((eq (car form) :vector) (map 'vector #'deserialize (cdr form)))
    ((eq (car form) :array)
     (let ((arr (make-array (second form))))
       (loop for i below (array-total-size arr) for v in (third form)
             do (setf (row-major-aref arr i) (deserialize v)))
       arr))
    ((eq (car form) :hash)
     (let ((h (make-hash-table :test (second form))))
       (loop for (k v) on (cddr form) by #'cddr do (setf (gethash (deserialize k) h) (deserialize v)))
       h))
    (t (cons (deserialize (car form)) (deserialize (cdr form))))))

(defun save-object (object path)
  "Serialize OBJECT (via SERIALIZE) and write it readably to PATH, replacing any
existing file.  Returns T on success, NIL if the write failed."
  (ignoring-errors ("save-object")
   (with-open-file (s path :direction :output :if-exists :supersede :if-does-not-exist :create)
     (let ((*print-readably* t)) (prin1 (serialize object) s)))   ; readably: an escapee fails loud
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
