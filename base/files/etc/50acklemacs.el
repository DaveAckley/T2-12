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

;;;;;;;
;;; go.el
;; Written in prehistory by Dave when he didn't know emacs lisp for squat

(defconst quarry-current-level nil)
;; Sadly, mode-line-format won't display numbers.
(defconst quarry-level-string nil)
(defconst quarry-generation-string 0)

(defvar quarry-source-buffer nil)

(defvar quarry-map nil "Keybindings for quarry window.")

(or nil; quarry-map DEBUG
    (progn
      (setq quarry-map (make-keymap))
      (define-key quarry-map " " 'quarry-forward)
      (define-key quarry-map "n" 'quarry-next)
      (define-key quarry-map "b" 'quarry-prev)
      (define-key global-map "\C-cs" 'quarry-start)
      (define-key global-map "\C-cv" 'quarry-display-start)
      (define-key global-map "\C-cd" 'timestamp-to-buffer)
      (define-key global-map "\C-c\C-d" 'timestamp1-to-buffer)
      (define-key global-map "\C-c;" 'quarry-comment-notestamp)
      (define-key global-map "\C-cg" 'quarry-go)
      (define-key global-map "\C-cs" 'quarry-start)
      ))

; Timestamp function
(defun timestamp-to-buffer ()
  (interactive)
  (insert (current-time-string) " "))

(defun timestamp1-to-buffer ()
  (interactive)
  (insert (format-time-string "%Y%m%d%H%M ")))


(defun quarry-comment-notestamp ()
    "Insert /* 61/NOTES:87 */ or the like, getting a new number, leaving us
in the NOTES buffer"
    (interactive)
    (if (equal quarry-NOTES-buffer "")
        (setq quarry-NOTES-buffer (read-from-minibuffer "NOTES buffer name: " "NOTES")))
    (let ((nbuff (get-buffer quarry-NOTES-buffer)) bname bpoint btag qlevel)
      (if (null nbuff) (error "No NOTES buffer"))
      (setq bname (buffer-file-name nbuff))
      (if (null bname) (error "NOTES has no associated file"))
      (setq btag (quarry-file-last-dir bname))
      (save-excursion
        (set-buffer nbuff)
        (quarry-init-if-necessary)
        (setq qlevel (quarry-read-num))
        (goto-char (point-max))
        (quarry-go)
        (insert "\n\n\n")
        (backward-char 1)
        (timestamp-to-buffer))
      (indent-for-comment)
      (insert btag ":" (format "%d " qlevel))
      (my-bury-current-buffer)
      (switch-to-buffer nbuff)));61/NOTES:4

(defun quarry-go ()
  "[quarry-step++ ]"
  (interactive)
  (quarry-init-if-necessary)
  (let ((buf (current-buffer))
        (num (quarry-read-num))
        (atendp (>= (point) (point-max)))
        (foo nil))

    (set-buffer buf)
    (insert "[")
    (insert (format "%d" num))
    (insert ": ")
    (setq foo (point))
    (insert "  :")
    (insert (format "%d" num))
    (insert "]")
    (and atendp (insert "\n")); Fri Feb 21 10:10:45 1997 try to avoid leaving
                                        ; lines w/o newlines at EOF (to make diff/patch happy)
    (goto-char foo)
    (quarry-increment-num)))

(defun quarry-read-num ()
  "extract current level number"
  (interactive)
  (save-excursion
    (goto-char 2)
    (mark-word 1)
    (string-to-number (buffer-substring (point) (mark)))))

(defun quarry-kill-num ()
  "delete current level number"
  (interactive)
  (save-excursion
    (goto-char 2)
    (kill-word 1)))

(defun quarry-replace-num (num)
  "set current level to num"
  (interactive)
  (save-excursion
    (quarry-kill-num)
    (goto-char 2)
    (insert (format "%d" num))))

(defun quarry-increment-num ()
  "increment and return level number"
  (interactive)
  (save-excursion
    (let ((num (quarry-read-num)))
      (setq num (+ num 1))
      (quarry-replace-num num)
      num)))

(defun quarry-check-type ()
  "T if this buffer inited for quarry"
  (interactive)
  (and (not (= (point-min) (point-max)))
       (string-equal (buffer-substring 1 2) "{")))

(defun quarry-init-if-necessary ()
  "inited if not inited"
  (interactive)
  (if (quarry-check-type)
      nil
    (progn (quarry-init)
           (goto-char (point-max)))))

(defun quarry-start ()
  "start or restart"
  (interactive)
  (save-excursion
    (if (quarry-check-type)
        (progn
          (goto-char 1)
          (kill-line 1)))
    (quarry-init)))

(defun quarry-init ()
  "once per quarry file"
  (interactive)
  (goto-char 1)
  (insert "{0}  -*-  mode: text; fill-column: 50;  -*-\n")
  (text-mode))
