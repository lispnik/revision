;;;; widgets.lisp --- window (framed container), button, static-text, and a demo
;;;; that hosts the outline + buttons with Tab focus cycling and command actions.

(in-package #:revision)

;;; --- window: a framed container with a title --------------------------------

(defclass window (container)
  ((title   :initarg :title :initform "" :accessor window-title
            :documentation "The window's title, drawn centred in its top frame.")
   (managed :initform nil :accessor window-managed)    ; hosted in a desktop (show close/resize affordances)
   (active  :initform t   :accessor window-active)      ; topmost/focused window (brighter frame)
   (cleanup :initform nil :accessor window-cleanup)     ; thunk run when the desktop closes it
   (scroll-target :initform nil :accessor window-scroll-target
                  :documentation "Scrollable child view whose position drives the window's frame scrollbar, or NIL.")
   (help    :initform :general :accessor window-help
            :documentation "Help-topic keyword shown for this window on F1 / the Help menu.")
   (kind    :initform nil :accessor window-kind
            :documentation "Builder keyword (e.g. :repl) identifying the window for desktop layout save/restore.")
   (number  :initform nil :accessor window-number)      ; 1..9 z-order number (Alt-N selects it)
   (zoomed  :initform nil :accessor window-zoomed)      ; filling the desktop?
   (saved-bounds :initform nil :accessor window-saved-bounds))  ; bounds to restore on un-zoom
  (:metaclass reactive-class)
  (:documentation "A framed, optionally desktop-managed top-level view: a titled container with a border,
an optional frame scrollbar, and z-order/zoom state for the desktop."))

(defgeneric frame-indicator (view)
  (:documentation "A short string a scroll-target view puts on its window's bottom
frame, left of the horizontal scrollbar (classic TV's TIndicator).  NIL for none.")
  (:method (view) (declare (ignore view)) nil))

(defmethod draw ((w window))
  (let* ((b (view-bounds w))
         (x0 (revision::rect-ax b)) (y0 (revision::rect-ay b))
         (x1 (1- (revision::rect-bx b))) (y1 (1- (revision::rect-by b)))
         (frame (if (window-active w) (role :frame) (role :frame-inactive))))
    (when (window-managed w) (%drop-shadow x0 y0 x1 y1))   ; TV-style drop shadow (under desktop windows)
    (loop for y from y0 to y1 do                       ; clear interior
      (loop for x from x0 to x1 do (%put-cell x y #\Space (role :normal))))
    (%box x0 y0 x1 y1 frame (window-active w))          ; double-line frame when active, single when not
    (%text-at (+ x0 (max 1 (floor (- (revision::rect-width b) (length (window-title w))) 2)))
              y0 (window-title w) frame)
    (dolist (sv (subviews w)) (draw sv))               ; children paint over the interior
    (when (window-scroll-target w)                     ; scrollbars on the right + bottom frame edges
      (let* ((tgt (window-scroll-target w)) (sb (role :scrollbar))
             (ind (frame-indicator tgt))               ; e.g. " 12:5 * INS " for an editor
             (iw (if ind (length ind) 0)) (hmax (scroll-hmax tgt)))
        (draw-vscroll x1 (1+ y0) (1- y1) (scroll-pos tgt) (scroll-max tgt))
        ;; classic TV: the scrollbar owns its end cells, drawn as box elbows in
        ;; the bar colour -- ┐ top-right, ┘ bottom-right, └ bottom-left
        (%put-cell x1 y0 #\┐ sb)
        (%put-cell x1 y1 #\┘ sb)
        (when (or ind (plusp hmax)) (%put-cell x0 y1 #\└ sb))
        ;; the position/insert indicator sits on the bottom frame, LEFT of the bar
        (when ind (%text-at (+ x0 1) y1 ind frame))
        (when (plusp hmax)                             ; horizontal bar, to the right of the indicator
          (draw-hscroll y1 (+ x0 1 iw) (1- x1) (scroll-hpos tgt) hmax))))
    (when (window-managed w)                            ; desktop affordances
      (%text-at (+ x0 1) y0 "[×]" frame)                ; close box
      (when (> (- x1 x0) 7) (%text-at (- x1 4) y0 (if (window-zoomed w) "[↓]" "[↑]") frame))  ; zoom box
      (when (and (window-number w) (<= 1 (window-number w) 9))    ; z-order number (Alt-N)
        (%put-cell (- x1 3) y1 (code-char (+ (char-code #\0) (window-number w))) frame)))))

;;; --- button: focusable, fires a command on Enter/Space ----------------------

(defclass button (view)
  ((label   :initarg :label   :accessor button-label
            :documentation "Text shown between the brackets, e.g. \"OK\" in [ OK ].")
   (command :initarg :command :accessor button-command
            :documentation "Command performed when the button is pressed (Enter/Space/click)."))
  (:metaclass reactive-class)
  (:documentation "A focusable push button that performs its COMMAND on Enter, Space, or a click."))

(defmethod focusable-p ((b button)) t)

(defmethod draw ((b button))
  (let* ((bb (view-bounds b))
         (attr (if (view-focused-p b) (role :button-focused) (role :button))))
    (fill-row b 0 0 (revision::rect-width bb) attr)
    (draw-text b 0 0 (format nil "[ ~a ]" (button-label b)) attr)))

(defmethod handle-event ((b button) (e key-event))
  (if (member (event-keysym e) (list :enter #\Space) :test #'equal)
      (progn (perform (button-command b) b e) (setf (handled-p e) t))
      (call-next-method)))

;;; --- static-text: a non-focusable label -------------------------------------

(defclass static-text (view)
  ((text :initarg :text :initform "" :accessor static-text-text
         :documentation "The string displayed on the single line; setting it repaints.")
   (role :initarg :role :initform :normal :reader static-text-role))
  (:metaclass reactive-class)
  (:documentation "A non-focusable one-line text label, drawn in ROLE's colours."))

(defmethod draw ((v static-text))
  ;; an empty :error line stays invisible (blends into the background) until set
  (let ((attr (if (and (zerop (length (static-text-text v))) (eq (static-text-role v) :error))
                  (role :normal)
                  (role (static-text-role v)))))
    (fill-row v 0 0 (revision::rect-width (view-bounds v)) attr)
    (draw-text v 0 0 (static-text-text v) attr)))

;;; --- label: static text linked to a control (TLabel) ------------------------
;;; TEXT marks its Alt-mnemonic with ~x~; Alt-x (from anywhere in the dialog)
;;; focuses the LINKed control (referenced by name), and the label brightens
;;; while that control is focused.

(defclass label (static-text)
  ((link :initarg :link :initform nil :accessor label-link))   ; NAME of the linked control
  (:metaclass reactive-class)
  (:documentation "Static text tied to a control (TLabel): its ~x~ Alt-mnemonic focuses the
linked control, and it brightens while that control is focused."))

(defun %label-hotkey (v)
  "The label's Alt-mnemonic (the char after the first ~, downcased), or NIL."
  (let* ((s (or (static-text-text v) "")) (p (position #\~ s)))
    (when (and p (< (1+ p) (length s))) (char-downcase (char s (1+ p))))))

(defun %label-linked-view (v)
  (and (label-link v) (find-view (view-root v) (label-link v))))

(defmethod draw ((v label))
  (let* ((b (view-bounds v)) (w (r-w b)) (ax (revision::rect-ax b)) (ay (revision::rect-ay b))
         (linked (%label-linked-view v))
         (text-c (role (if (and linked (view-focused-p linked)) :focused :label)))   ; brighten when linked control focused
         (hot-c  (role :menu-hotkey)))
    (fill-row v 0 0 w text-c)
    (loop with x = 0 and hot = nil
          for ch across (static-text-text v)
          while (< x w)
          do (if (char= ch #\~) (setf hot (not hot))
                 (progn (%put-cell (+ ax x) ay ch (if hot hot-c text-c)) (incf x))))))

(defun %dispatch-label-hotkey (c char)
  "If a label under container C has Alt-mnemonic CHAR, focus its linked control
and return T."
  (let ((labels '()))
    (labels ((walk (v) (when (typep v 'label) (push v labels))
               (when (typep v 'container) (mapc #'walk (subviews v)))))
      (walk c))
    (let ((lbl (find (char-downcase char) labels :key #'%label-hotkey)))
      (when lbl
        (let ((ctrl (%label-linked-view lbl)))
          (when ctrl (setf (container-focus (view-root c)) ctrl) (invalidate c) t))))))

(defmethod handle-event ((v label) (e mouse-down))   ; click a label to focus its linked control (TLabel)
  (let ((ctrl (%label-linked-view v)))
    (when ctrl (setf (container-focus (view-root v)) ctrl) (invalidate (view-root v))))
  (setf (handled-p e) t))

;;; --- input-line: an editable single-line text field -------------------------
;;; Text/caret/scroll are reactive (edits repaint), and an ON-CHANGE closure
;;; (a first-class handler) fires whenever the text changes -- data binding
;;; without GetData/SetData.

;;; A field validator: FILTER (char -> keep?) rejects keystrokes as typed; CHECK
;;; (string -> (values ok-p message)) validates the whole field on accept.
(defstruct (field-validator (:constructor %fv (&key filter check))) filter check)

(defvar *input-histories* (make-hash-table) "HISTORY-ID -> list of past entries (most recent first).")

(defclass input-line (view)
  ((text       :initarg :text :initform "" :accessor input-text
               :documentation "The field's current contents; reactive, so edits repaint.")
   (caret      :initform 0 :accessor input-caret
               :documentation "Insertion-point column within TEXT (0 = before the first char).")
   (scroll     :initform 0 :accessor input-scroll)         ; first visible column
   (on-change  :initarg :on-change :initform nil :accessor input-on-change
               :documentation "Closure (il) called whenever the text changes -- data binding.")
   (validator  :initarg :validator  :initform nil :accessor input-validator   ; field-validator or NIL
               :documentation "A FIELD-VALIDATOR (or NIL): FILTER rejects keystrokes, CHECK
validates the whole field on accept.")
   (history-id :initarg :history-id :initform nil :accessor input-history-id   ; key into *input-histories*
               :documentation "Key into *INPUT-HISTORIES* enabling Up/Down recall of past entries, or NIL.")
   (hist-pos   :initform nil :accessor input-hist-pos))
  (:metaclass reactive-class)
  (:documentation "An editable single-line text field with optional validation and history recall."))

(defmethod focusable-p ((il input-line)) t)

(defun input-history (il) (and (input-history-id il) (gethash (input-history-id il) *input-histories*)))
(defun input-remember (il)
  "Push the current text onto this field's history (deduped)."
  (let ((id (input-history-id il)) (s (input-text il)))
    (when (and id (plusp (length s)))
      (setf (gethash id *input-histories*) (cons s (remove s (gethash id *input-histories*) :test #'string=))))))
(defun input-recall (il delta)
  "Replace the field with the previous/next history entry."
  (let* ((h (input-history il)) (n (length h)))
    (when (plusp n)
      (let ((pos (cond ((null (input-hist-pos il)) (if (plusp delta) 0 (1- n)))
                       (t (max -1 (min n (+ (input-hist-pos il) delta)))))))
        (cond ((or (< pos 0) (>= pos n)) (setf (input-hist-pos il) nil (input-text il) ""))
              (t (setf (input-hist-pos il) pos (input-text il) (nth pos h))))
        (setf (input-caret il) (length (input-text il)))
        (input-scroll-fix il) (input-notify il)))))

(defun input-scroll-fix (il)
  (let ((b (view-bounds il)))
    (when b
      (let ((w (revision::rect-width b)) (c (input-caret il)) (sc (input-scroll il)))
        (cond ((< c sc) (setf (input-scroll il) c))
              ((>= c (+ sc w)) (setf (input-scroll il) (1+ (- c w)))))))))

(defun input-notify (il)
  "Fire IL's ON-CHANGE closure (if any) to signal that the text changed."
  (when (input-on-change il) (funcall (input-on-change il) il)))

(defun input-insert (il ch)
  (let ((v (input-validator il)))
    (when (or (null v) (null (field-validator-filter v)) (funcall (field-validator-filter v) ch))  ; reject filtered keys
      (let ((txt (input-text il)) (c (input-caret il)))
        (setf (input-text il)  (concatenate 'string (subseq txt 0 c) (string ch) (subseq txt c))
              (input-caret il) (1+ c))
        (input-scroll-fix il) (input-notify il)))))

(defun input-backspace (il)
  (let ((txt (input-text il)) (c (input-caret il)))
    (when (plusp c)
      (setf (input-text il)  (concatenate 'string (subseq txt 0 (1- c)) (subseq txt c))
            (input-caret il) (1- c))
      (input-scroll-fix il) (input-notify il))))

(defun input-delete (il)
  (let ((txt (input-text il)) (c (input-caret il)))
    (when (< c (length txt))
      (setf (input-text il) (concatenate 'string (subseq txt 0 c) (subseq txt (1+ c))))
      (input-notify il))))

(defun input-move (il delta)
  (setf (input-caret il) (min (length (input-text il)) (max 0 (+ (input-caret il) delta))))
  (input-scroll-fix il))

(defmethod draw ((il input-line))
  (let* ((b (view-bounds il)) (w (revision::rect-width b))
         (focused (view-focused-p il))
         (attr (if focused (role :input-focused) (role :input)))
         (txt (input-text il)) (sc (input-scroll il))
         (vis (subseq txt (min sc (length txt)) (min (length txt) (+ sc w)))))
    (fill-row il 0 0 w attr)
    (draw-text il 0 0 vis attr)
    (when (and focused revision:*screen*)              ; own the hardware cursor while focused
      (revision:set-cursor-pos revision:*screen*
                              (+ (revision::rect-ax b) (- (input-caret il) sc))
                              (revision::rect-ay b))
      (revision:show-cursor revision:*screen*))))

(defmethod handle-event ((il input-line) (e key-event))
  (let ((ks (event-keysym e)))
    (cond
      ((and (characterp ks) (graphic-char-p ks) (zerop (event-modifiers e)))
       (input-insert il ks) (setf (handled-p e) t))
      ((and (eql ks #\u) (logtest (event-modifiers e) revision::+md-ctrl+))    ; Ctrl-U: clear the whole field
       (setf (input-text il) "" (input-caret il) 0 (input-scroll il) 0)
       (input-notify il) (setf (handled-p e) t))
      ((eql ks :back)  (input-backspace il) (setf (handled-p e) t))
      ((eql ks :del)   (input-delete il)    (setf (handled-p e) t))
      ((eql ks :left)  (input-move il -1)   (setf (handled-p e) t))
      ((eql ks :right) (input-move il 1)    (setf (handled-p e) t))
      ((and (eql ks :up)   (input-history il)) (input-recall il 1)  (setf (handled-p e) t))   ; older
      ((and (eql ks :down) (input-history il)) (input-recall il -1) (setf (handled-p e) t))   ; newer
      ((eql ks :home)  (setf (input-caret il) 0) (input-scroll-fix il) (setf (handled-p e) t))
      ((eql ks :end)   (setf (input-caret il) (length (input-text il))) (input-scroll-fix il)
                       (setf (handled-p e) t))
      (t (call-next-method)))))               ; Enter/Tab/Esc bubble (submit, focus, quit)

;;; --- list-box: a scrollable, selectable flat list --------------------------
;;; Like INPUT-LINE it dispatches keys directly (no keymap); SELECTED/TOP are
;;; reactive, and Enter calls an ON-ACTIVATE closure with the chosen item.

(defclass list-box (view)
  ((items       :initarg :items :initform '() :accessor list-items
                :documentation "The list of item strings displayed, one per row.")
   (selected    :initform 0 :accessor list-selected
                :documentation "Index of the currently highlighted item.")
   (top         :initform 0 :accessor list-top            ; first visible row
                :documentation "Index of the first visible row (vertical scroll offset).")
   (hleft       :initform 0 :accessor list-hleft)          ; horizontal scroll offset (cols)
   (on-activate :initarg :on-activate :initform nil :accessor list-on-activate
                :documentation "Closure (lb item) called on Enter with the chosen item.")
   (on-select   :initarg :on-select   :initform nil :accessor list-on-select)     ; fired when selection moves
   (on-type     :initarg :on-type     :initform nil :accessor list-on-type)       ; (lb CHAR|:back) -> type-ahead
   (on-inspect  :initarg :on-inspect  :initform nil :accessor list-on-inspect))   ; (lb ITEM) -> open the inspector (Alt-I)
  (:metaclass reactive-class)
  (:documentation "A scrollable, selectable flat list; Enter activates the selected item."))

(defmethod focusable-p ((lb list-box)) t)

(defun list-scroll-fix (lb)
  "Adjust LIST-TOP so the selected item stays within the visible rows."
  (let ((b (view-bounds lb)))
    (when b
      (let ((h (r-h b)) (sel (list-selected lb)) (top (list-top lb)))
        (cond ((< sel top) (setf (list-top lb) sel))
              ((>= sel (+ top h)) (setf (list-top lb) (1+ (- sel h)))))))))

(defun list-notify (lb) (when (list-on-select lb) (funcall (list-on-select lb) lb)))

(defun list-move (lb delta)
  (let ((n (length (list-items lb))))
    (when (plusp n)
      (setf (list-selected lb) (min (1- n) (max 0 (+ (list-selected lb) delta))))
      (list-scroll-fix lb) (list-notify lb))))

(defmethod draw ((lb list-box))
  (let* ((b (view-bounds lb)) (h (revision::rect-height b)) (w (revision::rect-width b))
         (active (view-focused-p lb)) (items (list-items lb)) (top (list-top lb)))
    (dotimes (row h)
      (let* ((i (+ top row))
             (sel (and (= i (list-selected lb)) active))
             (attr (if sel (role :focused) (role :normal))))
        (fill-row lb 0 row w attr)
        (when (< i (length items))
          (draw-text lb 1 row (%hclip (nth i items) (list-hleft lb)) attr))))))

(defun %list-maxwidth (lb) (1+ (reduce #'max (list-items lb) :key #'length :initial-value 0)))  ; +1 indent

(defmethod handle-event ((lb list-box) (e key-event))
  (let ((ks (event-keysym e)) (n (length (list-items lb))))
    (cond
      ((eql ks :up)    (list-move lb -1) (setf (handled-p e) t))
      ((eql ks :down)  (list-move lb 1)  (setf (handled-p e) t))
      ((eql ks :home)  (setf (list-selected lb) 0) (list-scroll-fix lb) (list-notify lb) (setf (handled-p e) t))
      ((eql ks :end)   (setf (list-selected lb) (max 0 (1- n))) (list-scroll-fix lb) (list-notify lb) (setf (handled-p e) t))
      ((eql ks :left)  (scroll-hto lb (- (list-hleft lb) 8)) (setf (handled-p e) t))
      ((eql ks :right) (scroll-hto lb (+ (list-hleft lb) 8)) (setf (handled-p e) t))
      ((eql ks :enter) (when (and (list-on-activate lb) (< (list-selected lb) n))
                         (funcall (list-on-activate lb) lb (nth (list-selected lb) (list-items lb))))
                       (setf (handled-p e) t))
      ((and (list-on-inspect lb) (characterp ks) (char-equal ks #\i)         ; Alt-I: open the focused item in the inspector
            (logtest (event-modifiers e) revision::+md-alt+))
       (when (< (list-selected lb) n)
         (funcall (list-on-inspect lb) lb (nth (list-selected lb) (list-items lb))))
       (setf (handled-p e) t))
      ;; type-ahead: forward printable keys / Backspace to an owner (e.g. a filter field)
      ((and (list-on-type lb) (characterp ks) (graphic-char-p ks) (zerop (event-modifiers e)))
       (funcall (list-on-type lb) lb ks) (setf (handled-p e) t))
      ((and (list-on-type lb) (eql ks :back))
       (funcall (list-on-type lb) lb :back) (setf (handled-p e) t))
      (t (call-next-method)))))

;;; --- mouse: click to focus/select/press, wheel to scroll -------------------

(defmethod handle-event ((b button) (e mouse-down))
  (perform (button-command b) b e) (setf (handled-p e) t))

(defmethod handle-event ((il input-line) (e mouse-down))
  (setf (input-caret il) (max 0 (min (length (input-text il))
                                     (+ (input-scroll il) (mouse-col il e)))))
  (input-scroll-fix il) (setf (handled-p e) t))

(defmethod handle-event ((lb list-box) (e mouse-down))
  (let ((row (+ (list-top lb) (mouse-row lb e))))
    (when (and (>= row 0) (< row (length (list-items lb))))
      (setf (list-selected lb) row) (list-scroll-fix lb) (list-notify lb)))
  (setf (handled-p e) t))

(defmethod handle-event ((lb list-box) (e wheel-event))
  (list-move lb (* 3 (event-delta e))) (setf (handled-p e) t))

;;; --- a command that reaches across the window to the outline ----------------

(define-command collapse-all (v e)
  (let ((ol (find-view (view-root v) 'tree)))     ; locate the named outline anywhere in the tree
    (when (typep ol 'outline)
      (dolist (root (outline-roots ol))           ; collapse everything below each root
        (labels ((collapse (n)
                   (mapc #'collapse (revision:outline-node-children n))
                   (setf (revision:outline-node-expanded n) nil)))
          (mapc #'collapse (revision:outline-node-children root))))
      (setf (outline-focused ol) 0)
      (invalidate ol))))
