;;;; events.lisp --- events as a class hierarchy, plus terminal-event translation.
;;;;
;;;; Input/system events are CLOS classes dispatched on (view x event) with no
;;;; type tags (see HANDLE-EVENT in view.lisp).  TRANSLATE reuses the base
;;;; terminal decoder and maps its raw key codes to keysyms (special keys ->
;;;; keywords, printable -> characters).

(in-package #:revision)

;;; ---------------------------------------------------------------------------
;;; Events as a class hierarchy -- dispatched on (view x event), no type tags.
;;; ---------------------------------------------------------------------------

(defclass event ()
  ((handled :initform nil :accessor handled-p
            :documentation "Set true once a HANDLE-EVENT method consumes the event, stopping bubbling."))
  (:documentation "Base class for input/system events dispatched to views via HANDLE-EVENT."))
(defclass key-event (event)
  ((keysym    :initarg :keysym    :reader event-keysym
              :documentation "The key: a character, or a keyword for a special key (:up :enter :f1 …).")
   (modifiers :initarg :modifiers :initform 0 :reader event-modifiers
              :documentation "Bitmask of held modifiers (+MD-CTRL+ / +MD-ALT+ / +MD-SHIFT+)."))
  (:documentation "A key-press event; its (KEYSYM . MODIFIERS) form the token matched against keymaps."))
(defclass mouse-event (event)
  ((where   :initarg :where   :reader event-where
            :documentation "Cell position of the pointer (a TPOINT in screen coordinates).")
   (buttons :initarg :buttons :initform 0 :reader event-buttons))
  (:documentation "Base class for mouse events; EVENT-WHERE gives the pointer's cell position."))
(defclass mouse-down (mouse-event) ((double :initarg :double :initform nil :reader event-double))
  (:documentation "A mouse button-press event (EVENT-DOUBLE is true for the 2nd click of a double-click)."))
(defclass mouse-up   (mouse-event) ())
(defclass mouse-move (mouse-event) ())
(defclass wheel-event (mouse-event) ((delta :initarg :delta :reader event-delta
                                            :documentation "Scroll amount/direction (negative = up, positive = down)."))
  (:documentation "A mouse-wheel scroll event; EVENT-DELTA gives the scroll direction and magnitude."))
(defclass command-event (event) ((command :initarg :command :reader event-command)))
(defclass broadcast-event (event)
  ((id :initarg :id :reader event-id) (info :initarg :info :initform nil :reader event-info)))
(defclass idle-event (event) ())
(defclass paste-event (event)
  ((text :initarg :text :initform "" :reader event-text
         :documentation "The pasted block as one string (a bracketed-paste payload)."))
  (:documentation "A bracketed-paste block delivered as a single event; EVENT-TEXT is the payload."))

;;; ---------------------------------------------------------------------------
;;; Terminal -> revision event translation.  Reuse revision's escape-sequence decoder;
;;; map its key codes to keysyms (special keys -> keywords, printable -> chars).
;;; ---------------------------------------------------------------------------

(defparameter *special-keys*
  (list (cons +kb-up+ :up)     (cons +kb-down+ :down)
        (cons +kb-left+ :left) (cons +kb-right+ :right)
        (cons +kb-enter+ :enter) (cons +kb-esc+ :esc)
        (cons +kb-home+ :home) (cons +kb-end+ :end)
        (cons +kb-pgup+ :pgup) (cons +kb-pgdn+ :pgdn)
        (cons +kb-tab+ :tab)   (cons +kb-shift-tab+ :shift-tab)
        (cons revision::+kb-back+ :back) (cons revision::+kb-del+ :del)
        (cons revision::+kb-ins+ :ins)
        (cons revision::+kb-f1+ :f1) (cons revision::+kb-f2+ :f2) (cons revision::+kb-f3+ :f3)
        (cons revision::+kb-f4+ :f4) (cons revision::+kb-f5+ :f5) (cons revision::+kb-f6+ :f6)
        (cons revision::+kb-f7+ :f7) (cons revision::+kb-f8+ :f8) (cons revision::+kb-f9+ :f9)
        (cons revision::+kb-f10+ :f10)))

(defun translate (tev)
  "Translate a revision event struct into a revision event object, or NIL to ignore."
  (let ((ty (revision::iev-type tev)))
    (cond
      ((= ty +ev-key-down+)
       (let* ((k (revision::iev-key-code tev)) (c (revision::iev-char-code tev))
              (m (revision::iev-modifiers tev))
              (ks (or (cdr (assoc k *special-keys*)) (and (plusp c) (code-char c)))))
         ;; Normalise a Ctrl-letter: terminals deliver it as a control character
         ;; (code 1-26); present it as the base letter with +md-ctrl+, so Ctrl lives
         ;; only in the modifiers -- one encoding, like Shift+Del or Alt-X.
         (when (and (characterp ks) (<= 1 (char-code ks) 26))
           (setf ks (code-char (+ (char-code ks) 96))
                 m  (logior m revision::+md-ctrl+)))
         (and ks (make-instance 'key-event :keysym ks :modifiers m))))
      ((= ty +ev-mouse-wheel+)
       (make-instance 'wheel-event :delta (revision::iev-wheel tev) :where (%where tev)))
      ((= ty revision::+ev-mouse-down+)
       (make-instance 'mouse-down :where (%where tev) :buttons (revision::iev-mouse-buttons tev)))
      ((= ty revision::+ev-mouse-up+)
       (make-instance 'mouse-up :where (%where tev) :buttons (revision::iev-mouse-buttons tev)))
      ((member ty (list revision::+ev-mouse-move+ revision::+ev-mouse-auto+))
       (make-instance 'mouse-move :where (%where tev) :buttons (revision::iev-mouse-buttons tev)))
      ((= ty +ev-paste+)
       (make-instance 'paste-event :text (or (revision::iev-info tev) "")))
      (t nil))))

(defun %where (tev)
  "Mouse position of TEV as a (X . Y) cons in screen coordinates."
  (let ((p (revision::iev-mouse-where tev)))
    (cons (revision::point-x p) (revision::point-y p))))
