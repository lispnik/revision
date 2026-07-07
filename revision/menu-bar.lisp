;;;; menu-bar.lisp --- the desktop's pull-down menu bar.
;;;;
;;;; Pull-down menus with Alt-hotkeys, in-menu access keys, and global accelerators.
;;;; A menu's items are data; accelerators are compiled into a keymap so they run
;;;; through the same PERFORM machinery as view keybindings.  Drawing renders the
;;;; bar titles and the (possibly nested) dropdown boxes; keyboard and mouse handlers
;;;; drive navigation and invoke the selected item's command.

(in-package #:revision)

;;; --- menu bar (pull-down menus with hotkeys / accelerators) -----------------
;;; A menu is (LABEL . ITEMS); its hotkey (Alt-X) is the label's first letter.
;;; An item is (LABEL THUNK &optional ACCEL ENABLED): ACCEL is a global-shortcut
;;; keysym (e.g. (ctrl #\o)); ENABLED a thunk -> generalized boolean (or NIL).

(defclass menu-bar (view)
  ((menus  :initarg :menus :initform '() :accessor menu-menus)
   (active :initform 0 :accessor menu-active)                    ; open menu index, or NIL
   (sel    :initform 0 :accessor menu-sel)
   (sub    :initform nil :accessor menu-sub)                     ; open submenu index, or NIL
   (accel-km :initform nil :accessor mb-accel-km))               ; keymap: accelerator token -> command (built from MENUS)
  (:metaclass reactive-class)
  (:documentation "The desktop's top pull-down menu bar: draws the titles and dropdowns from MENUS,
handles hotkey/accelerator navigation, and invokes the selected item's command."))

(defun item-separator-p (it) (eq it :--))                                   ; :-- is a horizontal rule
(defun %strip-tildes (s) (if (find #\~ s) (remove #\~ s) s))
;; A menu label may mark its access key with a Turbo-Vision `~x~' bracket, e.g.
;; "C~a~scade" makes `a' the access key (so it doesn't clash with "Close").  The
;; tildes are stripped for display; an unmarked label uses its first letter.
(defun item-label    (it) (if (item-separator-p it) "" (%strip-tildes (first it))))
(defun item-mnemonic (it)
  "ITEM's access-key character: the char after a ~ marker, else the label's first char."
  (unless (item-separator-p it)
    (let* ((raw (first it)) (tilde (and (stringp raw) (position #\~ raw))))
      (cond ((and tilde (< (1+ tilde) (length raw))) (char raw (1+ tilde)))
            (t (let ((d (item-label it))) (and (plusp (length d)) (char d 0))))))))
(defun item-mnemonic-pos (it)
  "The display-string index of ITEM's access-key char (for the highlight)."
  (let* ((raw (first it)) (tilde (and (stringp raw) (position #\~ raw))))
    (if (and tilde (< (1+ tilde) (length raw))) tilde 0)))
(defun item-submenu-p (it) (and (consp it) (eq (second it) :submenu)))      ; (LABEL :submenu item...)
(defun item-thunk    (it) (and (consp it) (not (item-submenu-p it)) (second it)))
(defun item-accel    (it) (and (consp it) (not (item-submenu-p it)) (third it)))  ; submenu parents have no accel
(defun item-enabled  (it) (and (not (item-separator-p it))
                               (let ((f (and (consp it) (not (item-submenu-p it)) (fourth it))))
                                 (or (null f) (funcall f)))))
(defun item-submenu   (it) (cddr it))

(defun %menu-step (items sel dir)
  "Next selectable (non-separator) index from SEL in direction DIR, wrapping."
  (let ((n (length items)))
    (if (zerop n) 0
        (loop for i from 1 to n
              for k = (mod (+ sel (* dir i)) n)
              unless (item-separator-p (nth k items)) return k
              finally (return sel)))))

(defun %menu-mnemonic (items from ch)
  "The next enabled item index after FROM (wrapping) whose label starts with CH
\(case-insensitive), plus whether it is the ONLY match: (values INDEX SOLE-P), or
\(values NIL NIL) when nothing matches.  This is the in-menu access key -- an item's
first letter selects it, and (when unique) invokes it, classic Turbo-Vision style."
  (let ((matches (loop for it in items for i from 0
                       for m = (and (not (item-separator-p it)) (item-enabled it) (item-mnemonic it))
                       when (and m (char-equal m ch))
                         collect i)))
    (if matches
        (values (or (find-if (lambda (i) (> i from)) matches) (first matches))
                (null (cdr matches)))
        (values nil nil))))

(defparameter *menu-order*
  '("≡" "File" "Edit" "Lisp" "Tools" "Options" "Window" "Help")
  "Left-to-right order of the menu bar; menus not listed fall to the right.")

(defun %order-menus (menus)
  "Combine menus that share a title (so a module can contribute items to an existing
menu — e.g. add to Options or Help — with the contributed group set off by a rule),
then order the bar left-to-right by *MENU-ORDER*."
  (let ((merged '()))
    (dolist (m menus)
      (let ((cell (assoc (car m) merged :test #'string=)))
        (if cell
            (setf (cdr cell) (append (cdr cell) (list :--) (cdr m)))
            (setf merged (nconc merged (list (cons (car m) (copy-list (cdr m)))))))))
    (stable-sort merged #'<
                 :key (lambda (m) (or (position (car m) *menu-order* :test #'string=)
                                      most-positive-fixnum)))))
(defun menu-items   (mb) (cdr (nth (menu-active mb) (menu-menus mb))))
(defun menu-hotkey  (m)  (and (plusp (length (car m))) (char-downcase (char (car m) 0))))

;;; An accelerator is a keysym (e.g. :f5, or a Ctrl char like (ctrl #\o)) or a
;;; (KEYSYM . MODIFIER-FLAGS) cons for modified keys (e.g. (:f6 . shift) for
;;; Shift-F6).  ACCEL-MODS is the modifier set an accel expects to match against.
(defun accel-key  (a) (if (consp a) (car a) a))
(defun accel-mods (a)
  (cond ((consp a) (cdr a))
        ((and (characterp a) (< (char-code a) 32)) revision::+md-ctrl+)   ; a Ctrl char carries Ctrl intrinsically
        (t 0)))

(defun accel-label (a)
  (if (null a) ""
      (let ((ks (accel-key a)) (m (if (consp a) (cdr a) 0)))
        (concatenate 'string
                     (if (logtest m revision::+md-ctrl+)  "Ctrl+"  "")
                     (if (logtest m revision::+md-alt+)   "Alt+"   "")
                     (if (logtest m revision::+md-shift+) "Shift+" "")
                     (cond ((and (characterp ks) (< (char-code ks) 32)) (format nil "Ctrl+~a" (code-char (+ 64 (char-code ks)))))
                           ((characterp ks) (string-upcase (string ks)))
                           ((eq ks :del)  "Del") ((eq ks :ins) "Ins") ((eq ks :back) "Bksp")
                           (t (string-upcase (string ks))))))))

(defun menu-dropdown-width (items)
  (+ 4 (reduce #'max items :initial-value 8
               :key (lambda (it) (+ (length (item-label it))
                                    (if (item-accel it) (+ 2 (length (accel-label (item-accel it)))) 0))))))

(defmethod draw ((mb menu-bar))
  (let* ((b (view-bounds mb)) (w (r-w b)) (ax (revision::rect-ax b)) (ay (revision::rect-ay b))
         (bar (role :menu-bar)) (hot (role :menu-hotkey)) (x 1))
    (fill-row mb 0 0 w bar)
    (loop for menu in (menu-menus mb) for i from 0 do
      (let* ((label (car menu)) (open (eql i (menu-active mb))) (attr (if open (role :menu-selected) bar)))
        (%text-at (+ ax x) ay (format nil " ~a " label) attr)
        (%put-cell (+ ax x 1) ay (char label 0) (if open attr hot))   ; highlight the hotkey letter
        (when open
          (let* ((items (cdr menu)) (x0 (+ ax x)) (box-top (1+ ay)) (mw (menu-dropdown-width items))
                 (nb (role :menu)))                                    ; frame colour (same as the menu body)
            (flet ((draw-items (items bx bt sel)
                     ;; a bordered dropdown box: ┌─┐ top, │ … │ items, ├─┤ separators,
                     ;; └─┘ bottom -- like the original Turbo Vision (items inset 1 cell).
                     (let ((mww (menu-dropdown-width items)) (n (length items)))
                       (%drop-shadow bx bt (+ bx mww -1) (+ bt n 1))
                       (%put-cell bx bt #\┌ nb)                        ; top border
                       (loop for k from 1 below (1- mww) do (%put-cell (+ bx k) bt #\─ nb))
                       (%put-cell (+ bx mww -1) bt #\┐ nb)
                       (loop for it in items for r from 0 for ry = (+ bt 1 r) do
                         (%put-cell bx ry #\│ nb) (%put-cell (+ bx mww -1) ry #\│ nb)   ; side borders
                         (if (item-separator-p it)
                             (progn (%put-cell bx ry #\├ nb)           ; tee-connected divider
                                    (loop for k from 1 below (1- mww) do (%put-cell (+ bx k) ry #\─ nb))
                                    (%put-cell (+ bx mww -1) ry #\┤ nb))
                             (let* ((on (eql r sel)) (en (item-enabled it))
                                    (ia (cond ((and on en) (role :menu-selected)) (en (role :menu)) (t (role :menu-disabled)))))
                               (loop for k from 1 below (1- mww) do (%put-cell (+ bx k) ry #\Space ia))
                               (%text-at (+ bx 2) ry (item-label it) ia)
                               (when (and en (not on) (plusp (length (item-label it))))  ; access-key letter
                                 (let ((p (item-mnemonic-pos it)))
                                   (%put-cell (+ bx 2 p) ry (char (item-label it) p) hot)))
                               (cond ((item-submenu-p it) (%put-cell (+ bx mww -3) ry #\► ia))
                                     ((item-accel it) (let ((a (accel-label (item-accel it))))
                                                        (%text-at (+ bx mww -2 (- (length a))) ry a ia)))))))
                       (let ((by (+ bt n 1)))                          ; bottom border
                         (%put-cell bx by #\└ nb)
                         (loop for k from 1 below (1- mww) do (%put-cell (+ bx k) by #\─ nb))
                         (%put-cell (+ bx mww -1) by #\┘ nb)))))
              (draw-items items x0 box-top (menu-sel mb))
              (when (menu-sub mb)                                      ; second-level dropdown (overlaps the parent's right border)
                (let ((parent (nth (menu-sel mb) items)))
                  (when (item-submenu-p parent)
                    (draw-items (item-submenu parent) (+ x0 mw -1) (+ box-top 1 (menu-sel mb)) (menu-sub mb))))))))
        (incf x (+ 2 (length label)))))))

(defun %menu-run (mb thunk)
  "Close the menu, then run THUNK -- so the menu doesn't linger over the result."
  (setf (menu-active mb) nil (menu-sub mb) nil)
  (invalidate mb)
  (when thunk (funcall thunk)))

(defun menu-invoke-sel (mb)
  "Open a submenu parent, or invoke (and close on) a normal selected item."
  (let ((it (nth (menu-sel mb) (menu-items mb))))
    (cond ((null it) nil)
          ((item-submenu-p it) (setf (menu-sub mb) 0) (invalidate mb))
          ((and (item-enabled it) (item-thunk it)) (%menu-run mb (item-thunk it))))))

(defmethod handle-event ((mb menu-bar) (e key-event))
  (when (menu-active mb)
    (let ((ks (event-keysym e)) (n (length (menu-menus mb))) (items (menu-items mb)))
      (if (menu-sub mb)                                            ; navigating an open submenu
          (let ((subs (item-submenu (nth (menu-sel mb) items))))
            (cond
              ((eql ks :up)   (setf (menu-sub mb) (%menu-step subs (menu-sub mb) -1)) (invalidate mb) (setf (handled-p e) t))
              ((eql ks :down) (setf (menu-sub mb) (%menu-step subs (menu-sub mb) 1)) (invalidate mb) (setf (handled-p e) t))
              ((member ks '(:left :esc)) (setf (menu-sub mb) nil) (invalidate mb) (setf (handled-p e) t))
              ((eql ks :enter) (let ((it (nth (menu-sub mb) subs)))
                                 (%menu-run mb (and it (item-enabled it) (item-thunk it))))
                               (setf (handled-p e) t))
              ((and (characterp ks) (graphic-char-p ks) (zerop (event-modifiers e)))  ; access key
               (multiple-value-bind (idx sole) (%menu-mnemonic subs (or (menu-sub mb) 0) ks)
                 (when idx
                   (setf (menu-sub mb) idx) (invalidate mb) (setf (handled-p e) t)
                   (when sole (let ((it (nth idx subs)))
                               (%menu-run mb (and it (item-enabled it) (item-thunk it))))))))))
          (cond
            ((eql ks :left)  (setf (menu-active mb) (mod (1- (menu-active mb)) n) (menu-sel mb) 0 (menu-sub mb) nil) (invalidate mb) (setf (handled-p e) t))
            ((eql ks :right) (let ((it (nth (menu-sel mb) items)))
                               (if (item-submenu-p it) (setf (menu-sub mb) 0)
                                   (setf (menu-active mb) (mod (1+ (menu-active mb)) n) (menu-sel mb) 0)))
                             (invalidate mb) (setf (handled-p e) t))
            ((eql ks :up)    (setf (menu-sel mb) (%menu-step items (menu-sel mb) -1) (menu-sub mb) nil) (invalidate mb) (setf (handled-p e) t))
            ((eql ks :down)  (setf (menu-sel mb) (%menu-step items (menu-sel mb) 1) (menu-sub mb) nil) (invalidate mb) (setf (handled-p e) t))
            ((eql ks :enter) (menu-invoke-sel mb) (setf (handled-p e) t))
            ((and (characterp ks) (graphic-char-p ks) (zerop (event-modifiers e)))  ; access key
             (multiple-value-bind (idx sole) (%menu-mnemonic items (menu-sel mb) ks)
               (when idx
                 (setf (menu-sel mb) idx (menu-sub mb) nil) (invalidate mb) (setf (handled-p e) t)
                 (when sole (menu-invoke-sel mb))))))))))

(defun menu-hotkey-index (mb ch)
  (position (char-downcase ch) (menu-menus mb) :key #'menu-hotkey))

(defun %accel-command (item)
  "A command that runs menu ITEM's thunk, enabled iff the item's guard is.  Registered in
*COMMANDS* under a label-derived name, so menu actions join the same registry as the
keymap commands.  Enablement flows through the command's predicate -- PERFORM's own
COMMAND-ENABLED-P check gates it, so there is no second hand-rolled check in the action."
  (register-command (intern (format nil "MENU ~a" (item-label item)) :keyword)
                    (lambda (v e) (declare (ignore v e)) (funcall (item-thunk item)))
                    (item-label item)
                    (lambda () (item-enabled item))))

(defun %menu-accel-keymap (menus)
  "Build a keymap binding each accelerated menu item's key-token to a command that
runs the item's thunk, so menu accelerators use the SAME keymap/PERFORM machinery
as view keymaps.  Warns on a duplicate accelerator instead of silently shadowing."
  (let ((km (make-instance 'keymap)))
    (labels ((walk (items)
               (dolist (it items)
                 (cond
                   ((item-submenu-p it) (walk (item-submenu it)))
                   ((and (consp it) (not (item-separator-p it)) (item-accel it))
                    (let ((tok (key-token (item-accel it))))
                      (when (gethash tok (keymap-bindings km))
                        (warn "revision: duplicate menu accelerator ~a (~s)"
                              (accel-label (item-accel it)) (item-label it)))
                      (setf (gethash tok (keymap-bindings km)) (%accel-command it))))))))
      (dolist (menu menus) (walk (cdr menu))))
    km))

(defmethod initialize-instance :after ((mb menu-bar) &key)
  (setf (mb-accel-km mb) (%menu-accel-keymap (menu-menus mb))))

(defun menu-accel-command (mb ks mods)
  "The command bound to accelerator KS+MODS in MB's accelerator keymap, or NIL."
  (and (mb-accel-km mb) (keymap-lookup (mb-accel-km mb) ks mods)))

(defun menu-title-x (mb i)
  (let ((x 1)) (dotimes (k i x) (incf x (+ 2 (length (car (nth k (menu-menus mb)))))))))

(defun menu-dropdown-cols (mb)
  (when (menu-active mb)
    (values (menu-title-x mb (menu-active mb)) (menu-dropdown-width (menu-items mb)))))

(defun menu-sub-cols (mb)
  "(values SX SY0 COUNT WIDTH) of the open submenu dropdown, or NIL.  SY0 is the
box's top-border row; its items occupy rows SY0+1 .. SY0+COUNT."
  (when (and (menu-active mb) (menu-sub mb))
    (let ((parent (nth (menu-sel mb) (menu-items mb))))
      (when (item-submenu-p parent)
        (multiple-value-bind (x0 mw) (menu-dropdown-cols mb)
          (values (+ x0 mw -1) (+ 2 (menu-sel mb)) (length (item-submenu parent))
                  (menu-dropdown-width (item-submenu parent))))))))

(defun menu-hit-p (mb x y)
  (or (zerop y)
      (and (menu-active mb) (>= y 1) (<= y (+ 2 (length (menu-items mb))))    ; main box incl. borders
           (multiple-value-bind (x0 mw) (menu-dropdown-cols mb)
             (and x0 (>= x x0) (< x (+ x0 mw)))))
      (multiple-value-bind (sx sy0 cnt smw) (menu-sub-cols mb)   ; open submenu box incl. borders
        (and sx (>= x sx) (< x (+ sx smw)) (>= y sy0) (<= y (+ sy0 cnt 1))))))

(defmethod handle-event ((mb menu-bar) (e mouse-down))
  (let ((col (mouse-col mb e)) (row (mouse-row mb e)))
    (multiple-value-bind (sx sy0 cnt smw) (menu-sub-cols mb)
      (cond
        ((and sx (>= col sx) (< col (+ sx smw)) (> row sy0) (<= row (+ sy0 cnt)))   ; submenu item (row sy0 is the border)
         (let* ((idx (- row sy0 1)) (subs (item-submenu (nth (menu-sel mb) (menu-items mb)))) (it (nth idx subs)))
           (setf (menu-sub mb) idx) (invalidate mb)
           (%menu-run mb (and it (item-enabled it) (item-thunk it)))))
        ((zerop row)                                  ; clicked a title -> open that menu
         (let ((x 1))
           (loop for menu in (menu-menus mb) for i from 0 do
             (let ((tw (+ 2 (length (car menu)))))
               (when (and (>= col x) (< col (+ x tw)))
                 (setf (menu-active mb) i (menu-sel mb) 0 (menu-sub mb) nil) (invalidate mb) (return))
               (incf x tw)))))
        ((menu-active mb)                             ; clicked a dropdown item -> invoke / open submenu
         (let ((idx (- row 2)) (items (menu-items mb)))   ; row 1 is the top border; item 0 is at row 2
           (when (and (>= idx 0) (< idx (length items)))
             (setf (menu-sel mb) idx (menu-sub mb) nil) (invalidate mb) (menu-invoke-sel mb))))))
    (setf (handled-p e) t)))
