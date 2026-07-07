;;;; draw.lisp --- theming, drawing primitives, chrome, and the scroll protocol.
;;;;
;;;; Colours are named semantic roles resolved through *THEME* (a plist) instead
;;;; of byte palettes walked up the owner chain.  The drawing helpers write packed
;;;; cells straight to revision's back buffer, clipped to a view's bounds, and are
;;;; grapheme-aware (wide glyphs reserve their second cell).  A scrollable view
;;;; answers the SCROLL-* protocol; a window draws a scrollbar bound to it.

(in-package #:revision)

;;; ---------------------------------------------------------------------------
;;; Theming: colours are named roles resolved through *THEME* (a plist), instead
;;; of byte palettes walked up the owner chain.
;;; ---------------------------------------------------------------------------

;;; The classic Turbo Vision "blue window / grey dialog" palette (VGA 16-colour,
;;; IRGB order: 0 blk 1 blu 2 grn 3 cyn 4 red 5 mag 6 brn 7 lgray …).
(defparameter *theme*
  (list :normal          (revision:make-attr 7 1)     ; light grey on blue (window text)
        :focused         (revision:make-attr 15 3)    ; white on cyan (selected row)
        :frame           (revision:make-attr 15 1)    ; bright white on blue (active window)
        :frame-inactive  (revision:make-attr 7 1)     ; light grey on blue (background window)
        :menu-bar        (revision:make-attr 0 7)     ; black on light-grey (the menu bar)
        :menu            (revision:make-attr 0 7)     ; black on light-grey (dropdown)
        :menu-selected   (revision:make-attr 15 2)    ; white on green (highlighted item)
        :menu-hotkey     (revision:make-attr 4 7)     ; red on light-grey (Alt-hotkey letter)
        :menu-disabled   (revision:make-attr 8 7)     ; dim grey on light-grey
        :status          (revision:make-attr 0 3)     ; black on cyan (status line)
        :button          (revision:make-attr 15 2)    ; white on green (button)
        :button-focused  (revision:make-attr 14 2)    ; yellow on green (focused/default button)
        :label           (revision:make-attr 14 1)    ; yellow on blue
        :input           (revision:make-attr 0 3)     ; black on cyan (input field)
        :input-focused   (revision:make-attr 15 3)    ; white on cyan
        :error           (revision:make-attr 15 4)    ; white on red
        :desktop         (revision:make-attr 8 1)     ; dim ░ pattern on blue (the desktop)
        :scrollbar       (revision:make-attr 0 3)     ; scrollbar track + arrows + corners: black on cyan (classic TV)
        :scrollbar-thumb (revision:make-attr 14 3))   ; the position indicator █: yellow on cyan
  "Role -> packed attribute.")

;;; The classic "grey dialog" palette, bound over *THEME* while a dialog and its
;;; children draw, so dialogs read grey instead of the blue window scheme.
(defparameter *dialog-theme*
  (list :normal          (revision:make-attr 0 7)     ; black on light-grey
        :focused         (revision:make-attr 15 3)    ; white on cyan
        :frame           (revision:make-attr 0 7)     ; black on light-grey (active)
        :frame-inactive  (revision:make-attr 8 7)     ; dim grey on light-grey
        :menu-bar        (revision:make-attr 0 7)
        :menu            (revision:make-attr 0 7)
        :menu-selected   (revision:make-attr 15 2)
        :menu-hotkey     (revision:make-attr 4 7)
        :menu-disabled   (revision:make-attr 8 7)
        :status          (revision:make-attr 0 7)     ; dialog help text on grey
        :button          (revision:make-attr 15 2)    ; green button
        :button-focused  (revision:make-attr 14 2)    ; yellow on green (default)
        :label           (revision:make-attr 0 7)     ; black on light-grey
        :input           (revision:make-attr 0 3)     ; black on cyan (input field)
        :input-focused   (revision:make-attr 15 3)    ; white on cyan
        :error           (revision:make-attr 15 4)    ; white on red
        :desktop         (revision:make-attr 8 1)
        :scrollbar       (revision:make-attr 8 7)
        :scrollbar-thumb (revision:make-attr 0 7))
  "Role -> attribute while a DIALOG draws (the grey-dialog palette).")

(defun role (key)
  "The colour attribute the current *THEME* assigns to the semantic role KEY (e.g. :normal,
:focused, :status, :frame), or a plain grey-on-black default when the role is unset."
  (or (getf *theme* key) (revision:make-attr 7 0)))

;;; ---------------------------------------------------------------------------
;;; Drawing helpers (write packed cells straight to revision's back buffer,
;;; clipped to the view's bounds).
;;; ---------------------------------------------------------------------------

(defun %put-code (x y code attr)
  "Like %PUT-CELL but writes a raw character CODE (e.g. revision::+wide-cont+, the
sentinel marking the second cell of a double-width glyph)."
  (when revision:*screen*
    (revision:screen-cell-set revision:*screen* x y (revision::cell-make-code code attr))))

(defun %put-cell (x y char attr) (%put-code x y (char-code char) attr))

(defun draw-text (view col row string attr)
  "Write STRING at view-local (COL,ROW), clipped to VIEW's width.  Grapheme-aware:
a multi-code-point cluster (skin-tone / ZWJ emoji, combining marks) is interned as
one display unit, and a double-width glyph reserves its second cell with the
+wide-cont+ sentinel (so the flush doesn't overwrite its right half)."
  (let* ((b (view-bounds view))
         (ax (revision::rect-ax b)) (gy (+ (revision::rect-ay b) row))
         (w (revision::rect-width b))
         (n (length string)) (i 0) (x col))
    (loop while (and (< i n) (< x w)) do
      (let* ((j (revision::next-grapheme-col string i))       ; end of the grapheme at I
             (g (subseq string i j))
             (code (if (= (- j i) 1) (char-code (char string i)) (revision::intern-grapheme g)))
             (cw (max 1 (revision::grapheme-width g))))
        (%put-code (+ ax x) gy code attr)
        (when (and (= cw 2) (< (1+ x) w))                     ; wide glyph: reserve the 2nd cell
          (%put-code (+ ax x 1) gy revision::+wide-cont+ attr))
        (setf i j) (incf x cw)))))

(defun %hclip (s hl) (if (< hl (length s)) (subseq s hl) ""))   ; drop HL leading columns (horizontal scroll)

(defun fill-row (view col row width attr)
  (let* ((b (view-bounds view))
         (gx (+ (revision::rect-ax b) col)) (gy (+ (revision::rect-ay b) row)))
    (dotimes (i width) (%put-cell (+ gx i) gy #\Space attr))))

;;; ---------------------------------------------------------------------------
;;; Chrome helpers (box, drop shadow, centred text).
;;; ---------------------------------------------------------------------------

(defun %box (x0 y0 x1 y1 attr &optional double)
  "Draw a box; DOUBLE uses the ═║╔╗╚╝ line set (classic active window), else ─│┌┐."
  (multiple-value-bind (tl hz tr vt bl br)
      (if double (values #\╔ #\═ #\╗ #\║ #\╚ #\╝) (values #\┌ #\─ #\┐ #\│ #\└ #\┘))
    (%put-cell x0 y0 tl attr) (%put-cell x1 y0 tr attr)
    (%put-cell x0 y1 bl attr) (%put-cell x1 y1 br attr)
    (loop for x from (1+ x0) below x1 do (%put-cell x y0 hz attr) (%put-cell x y1 hz attr))
    (loop for y from (1+ y0) below y1 do (%put-cell x0 y vt attr) (%put-cell x1 y vt attr))))

(defun %darken-cell (x y)
  "Darken the back-buffer cell at (X,Y), keeping its glyph -- one drop-shadow cell."
  (let ((s revision:*screen*))
    (when (and s (>= x 0) (< x (revision:screen-width s)) (>= y 0) (< y (revision:screen-height s)))
      (let* ((back (revision::screen-back s)) (idx (+ x (* y (revision:screen-width s)))))
        (setf (aref back idx)
              (revision::cell-make-code (revision::cell-char-code (aref back idx)) (revision:make-attr 8 0)))))))

(defun %drop-shadow (x0 y0 x1 y1)
  "Paint a Turbo-Vision drop shadow: two columns down the right edge, one row
along the bottom, offset one cell past the (X0,Y0)-(X1,Y1) box."
  (loop for y from (1+ y0) to (1+ y1) do (%darken-cell (1+ x1) y) (%darken-cell (+ x1 2) y))
  (loop for x from (+ x0 2) to (+ x1 2) do (%darken-cell x (1+ y1))))

(defun %text-at (x y string attr)
  (loop for i below (length string) do (%put-cell (+ x i) y (char string i) attr)))

;;; ---------------------------------------------------------------------------
;;; The scroll protocol + scrollbar rendering.
;;; ---------------------------------------------------------------------------

;;; A scrollable view answers this protocol; a window draws a scrollbar bound to
;;; its SCROLL-TARGET, and the desktop maps clicks/drags on it to SCROLL-TO.
(defgeneric scroll-pos  (v) (:documentation "First visible row (the scroll offset)."))
(defgeneric scroll-max  (v) (:documentation "Maximum scroll offset (>= 0)."))
(defgeneric scroll-page (v) (:documentation "Number of visible rows."))
(defgeneric scroll-to   (v pos) (:documentation "Set the offset (clamped) and repaint."))

;;; The horizontal counterpart; a view with SCROLL-HMAX > 0 gets a bottom
;;; scrollbar too.  Default: no horizontal scrolling.
(defgeneric scroll-hpos  (v) (:method (v) (declare (ignore v)) 0))
(defgeneric scroll-hmax  (v) (:method (v) (declare (ignore v)) 0))
(defgeneric scroll-hpage (v) (:method (v) (declare (ignore v)) 1))
(defgeneric scroll-hto   (v pos) (:method (v pos) (declare (ignore v pos)) nil))

;;; Context-sensitive status-bar chips: a focused view may offer (LABEL . THUNK)
;;; actions the desktop appends to the status line.  Default: none.
(defgeneric status-hints (view)
  (:method (v) (declare (ignore v)) nil)
  (:documentation "The (LABEL . THUNK) action chips the focused VIEW contributes to the desktop status
bar; specialize to offer context actions.  Default: none."))

(defun draw-vscroll (x y0 y1 pos max)
  "Draw a vertical scrollbar in column X with arrows at rows Y0 (▲) and Y1 (▼)
and a thumb positioned by POS/MAX over the track between them."
  (let ((bar (role :scrollbar)) (thumb (role :scrollbar-thumb)))
    (when (> y1 y0)
      (%put-cell x y0 #\▲ bar)                        ; arrows share the track colour (classic TV)
      (%put-cell x y1 #\▼ bar)
      (let ((track (- y1 y0 1)))                       ; inner rows y0+1 .. y1-1
        (loop for r from 1 below (- y1 y0) do (%put-cell x (+ y0 r) #\▒ bar))
        (when (and (plusp max) (plusp track))
          (%put-cell x (+ y0 1 (max 0 (min (1- track) (floor (* pos (1- track)) max)))) #\█ thumb))))))

(defun draw-hscroll (y x0 x1 pos max)
  "Draw a horizontal scrollbar in row Y with arrows at cols X0 (◄) and X1 (►)
and a thumb positioned by POS/MAX over the track between them."
  (let ((bar (role :scrollbar)) (thumb (role :scrollbar-thumb)))
    (when (> x1 x0)
      (%put-cell x0 y #\◄ bar)                        ; arrows share the track colour (classic TV)
      (%put-cell x1 y #\► bar)
      (let ((track (- x1 x0 1)))                       ; inner cols x0+1 .. x1-1
        (loop for c from 1 below (- x1 x0) do (%put-cell (+ x0 c) y #\▒ bar))
        (when (and (plusp max) (plusp track))
          (%put-cell (+ x0 1 (max 0 (min (1- track) (floor (* pos (1- track)) max)))) y #\█ thumb))))))
