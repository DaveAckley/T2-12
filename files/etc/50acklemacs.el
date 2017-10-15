;;; I invented this damn tile.  Just shut up and use my customizations.

;;; Save lots of shell commands
(setq comint-input-ring-size 1000)

(menu-bar-mode -1)    ; I *never* use the stupid thing..
;;;(tool-bar-mode -1)    ; I *never* use the stupid thing..

;;; Plausible suggestions for code from the ACE folks
(setq-default indent-tabs-mode nil)

;;; how late am I?  Sometimes also helps keep serial lines from hanging up
(display-time)

(setq text-mode-hook '(lambda () (auto-fill-mode 1))) ; fill text files by default


;;;;;;;
;;; dired-sort-map.el --- in Dired: press s then s, x, t or n to sort by Size, eXtension, Time or Name
;; Copyright (C) 2002 by Free Software Foundation, Inc.
;; Author: Patrick Anderson

(defvar dired-sort-map (make-sparse-keymap))

(add-hook 'dired-mode-hook '(lambda () (define-key dired-mode-map "s" dired-sort-map)))
(add-hook 'dired-mode-hook '(lambda () (define-key dired-sort-map "s" '(lambda () "sort by Size" (interactive) (dired-sort-other (concat dired-listing-switches "S"))))))
(add-hook 'dired-mode-hook '(lambda () (define-key dired-sort-map "x" '(lambda () "sort by eXtension" (interactive) (dired-sort-other (concat dired-listing-switches "X"))))))
(add-hook 'dired-mode-hook '(lambda () (define-key dired-sort-map "t" '(lambda () "sort by Time" (interactive) (dired-sort-other (concat dired-listing-switches "t"))))))
(add-hook 'dired-mode-hook '(lambda () (define-key dired-sort-map "n" '(lambda () "sort by Name" (interactive) (dired-sort-other (concat dired-listing-switches ""))))))
(provide 'dired-sort-map)
;;;;;;;

;;; ^T
(defun dha-ctl-t ()
  (interactive)
  (transpose-chars -1)
  (forward-char 1))

;;; ^C^F
(defun dha-bury-current-buffer ()
  (interactive)
  (let (blist)
    (bury-buffer (current-buffer))
    (setq blist (buffer-list))
    (switch-to-buffer (car blist))))

(defun dha-list-last (l)
  (while (cdr l) (setq l (cdr l)))
  (car l))

;;; ^C^B
(defun dha-raise-bottom-buffer ()
  (interactive)
  (let ((lastb (dha-list-last (buffer-list))))
    (switch-to-buffer lastb)))

;;; Global key bindings

(global-unset-key "\^Xn")    ; I mistype this too much.
(global-unset-key "\^T")       ; make ^T always transpose

;;;; Private 'kill buffer'
;;; I don't really need zillions of registers,
;;; but I would like to have kill/yank functionality
;;; using just one other register, to avoid the
;;; 'sinking into the kill ring' problem.
;;; So make C-M-w copy the region into register K,
;;; and make C-M-y insert the contents of register K.

(defun dha-wipe-region ()
  (interactive)
  (copy-to-register ?K (point) (mark) nil))
(defun dha-yank-region ()
  (interactive)
  (insert-register ?K))

;;; Finally fucking make switch-to-buffer insist on an
;;; an existing buffer, unless given a prefix argument

(defun dha-switch-to-buffer (buf)
  (interactive
   (list (read-buffer
	  (if current-prefix-arg "Switch to buffer: " "Switch to existing buffer: ")
	  (buffer-name (other-buffer)) (not current-prefix-arg))))
  (switch-to-buffer buf))

(global-unset-key "\^Xb")    ; kill normal switch-to-buffer binding
(global-set-key "\^Xb" 'dha-switch-to-buffer) ; use mine instead

(global-unset-key "\M-\C-w")
(global-set-key "\M-\C-w" 'dha-wipe-region)
(global-set-key "\M-\C-y" 'dha-yank-region)

(global-set-key "\^C\^P" 'picture-mode)    ; enter picture mode

(global-set-key "\^T" 'dha-ctl-t)    ;  ALWAYS transpose PREVIOUS two chars
(global-set-key "\^C\^R" 'replace-string)   ; put replace on a key already!
(global-set-key "\^C\^F" 'dha-bury-current-buffer) ; like it says
(global-set-key "\^C\^B" 'dha-raise-bottom-buffer) ; like it says
(global-set-key "\C-xc" 'compile)    ; do compilation command
(global-set-key "\C-xt" 'auto-fill-mode)    ; toggle auto fill
(global-set-key "\C-x*" 'shell) ; start a sub shell (v19: not cmushell)

