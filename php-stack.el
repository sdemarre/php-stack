(require 'ov)
(setq php-stack-data nil)
(setq php-shell-buffer nil)
(setq php-stack-highlight-info nil)
(setq saved-buffer-before-php-shell nil)
(setq php-stack-current-source-line-buffer nil)
(setq skip-files-when-walking-stack nil)
(setq files-to-skip-when-walking-stack '("vendor/.*"))
(progn ;; this was used when we were relying on vagrant laravel, but is no longer needed
  (setq remote-prefix "/home/vagrant/assetManager/")
  (setq local-prefix "/home/serge/data/assetManagerSite")
  (setq remote-shell-rx "vagrant"))
(progn
  (setq remote-prefix "/root/asset-manager/")
  (setq local-prefix "~/data2/serge/docker/asset-manager-composer/asset-manager/")
  (setq remote-shell-rx "root"))
(setq remote-prefix-rx (concatenate 'string "^" remote-prefix))

(defun current-line ()
  (buffer-substring-no-properties (point-at-bol) (point-at-eol)))

(defmacro php-stack-index ()
  `(car php-stack-data))
(defmacro php-stack-file-infos ()
  `(cdr php-stack-data))
(defun full-previous-line ()
  (goto-char (point-at-bol))
  (backward-char 1)
  (goto-char (point-at-bol)))
(defun full-next-line ()
  (goto-char (point-at-eol))
  (forward-char 1)
  (goto-char (point-at-bol)))
(defun get-stack-info-at-point ()
  (interactive)
  (save-excursion
    (while (stack-info-line-p (current-line))
      (full-previous-line))
    (full-next-line)
    (let (all-stack-lines)
      (while (stack-info-line-p (current-line))
        (push (stack-info-line-p (current-line)) all-stack-lines)
        (full-next-line))
      (setq php-stack-data (cons 0 (vconcat (reverse all-stack-lines)))))))

(defun make-php-stack-info (file line)
  (list file line (current-buffer) (point-at-bol) (point-at-eol)))
(defun make-empty-stack-php-info ()
  (make-php-stack-info nil nil))
(defun stack-info-file (stack-info)
  (first stack-info))
(defun stack-info-line (stack-info)
  (second stack-info))
(defun stack-info-source-buffer (stack-info)
  (third stack-info))
(defun stack-info-source-buffer-start-pos (stack-info)
  (fourth stack-info))
(defun stack-info-source-buffer-end-pos (stack-info)
  (fifth stack-info))
(defun remote-to-local (filename)
  (replace-regexp-in-string remote-prefix-rx local-prefix filename))
(defun stack-info-line-p (line)
  (or (and (string-match-p remote-prefix-rx line)
           (let ((split-info (split-string line ":")))
             (when (cdr split-info)
               (make-php-stack-info (remote-to-local (car split-info))
                                    (string-to-int (cadr split-info))))))
      (and (string-match-p " *[0-9]+:.*at n/a:n/a" line) (make-empty-stack-php-info))
      (and (string-match-p " *[0-9]+:.*at[^:]+:[0-9]+" line)
           (let* ((split-info-1 (split-string line " at "))
                  (split-info (split-string (car (last split-info-1)) ":")))
             (make-php-stack-info (concatenate 'string local-prefix (car split-info))
                                  (string-to-int (cadr split-info)))))
      (and (string-match-p "^ *#[0-9]+ .+([0-9]+): .+" line)
           (let* ((split-info-1 (split-string line ": "))
                  (split-info (split-string (replace-regexp-in-string "^ +#[0-9]+ " "" (car split-info-1)) "(")))
             (when (cdr split-info)
               (make-php-stack-info (remote-to-local (car split-info))
                                    (string-to-int (cadr split-info))))))
      (and (string-match-p "^ *#[0-9]+ .internal function.: .+" line)
           (make-empty-stack-php-info))
      (and (string-match-p "^From .*:[0-9]+" line)
           (let ((split-info-1 (split-string line ":")))
             (make-php-stack-info (concatenate 'string local-prefix (cadr (split-string (car split-info-1))))
                                  (string-to-int (cadr split-info-1)))))
      (and (string-match-p (concatenate 'string ".* in " remote-prefix ".* on line [0-9]+") line)
           (let* ((split-info-1 (s-slice-at " in /home/vagrant" line))
                  (file-and-line (subseq (second split-info-1) 4))
                  (split-info (s-slice-at " on line" file-and-line)))
             (make-php-stack-info (remote-to-local (first split-info))
                                  (string-to-int (subseq (second split-info) 8)))))))

(defun clear-current-stack-line-highlight ()
  (when php-stack-current-source-line-buffer
    (with-current-buffer php-stack-current-source-line-buffer
      (ov-clear))))

(defun find-previous-stack-info-top ()
  (interactive)
  (setq php-shell-buffer (current-buffer))
  (while (not (stack-info-line-p (current-line)))
    (full-previous-line))
  (while (stack-info-line-p (current-line))
    (full-previous-line))
  (full-next-line)
  (start-php-stack-browse))

(defun should-display-current-stack-entry ()
  (let ((stack-info-file (stack-info-file (current-stack-info))))
    (and (stringp stack-info-file)
         (or (not skip-files-when-walking-stack)
             (not (some #'(lambda (skip-pattern) (string-match skip-pattern stack-info-file)) files-to-skip-when-walking-stack))))))

(defun move-to-next-stack-entry (move limit toggle-filter)
  (when toggle-filter
    (setq skip-files-when-walking-stack (not skip-files-when-walking-stack)))
  (let (found-stack-entry-to-display)
    (while (and php-stack-data
                (funcall limit)
                (not found-stack-entry-to-display))
      (funcall move)
      (setf found-stack-entry-to-display (should-display-current-stack-entry)))
    (if found-stack-entry-to-display
        (visit-current-php-stack-file t)
      (message "at bottom"))))
(defun highlight-previous-php-stack-entry (prefix)
  (interactive "p")
  (move-to-next-stack-entry #'(lambda () (decf (php-stack-index)))
                            #'(lambda () (> (php-stack-index) 0))
                            (= prefix 4)))
(defun highlight-next-php-stack-entry (prefix)
  (interactive "p")
  (move-to-next-stack-entry #'(lambda () (incf (php-stack-index)))
                            #'(lambda () (< (php-stack-index) (1- (length (php-stack-file-infos)))))
                            (= prefix 4)))

(defmacro my-save-excursion (&rest body)
  (let ((saved-buffer (gensym))
        (saved-point (gensym)))
    `(let ((,saved-buffer (current-buffer))
           (,saved-point (point)))
       ,@body
       (switch-to-buffer ,saved-buffer)
       (goto-char ,saved-point))))

(defun highlight-this-line-as-current-source-line ()
  (when (and php-stack-current-source-line-buffer
             (buffer-live-p php-stack-current-source-line-buffer))
    (my-save-excursion
     (switch-to-buffer php-stack-current-source-line-buffer)
     (ov-clear 'php-stack-current-source)
     (setf php-stack-current-source-line-buffer nil)))
  (ov-set (ov-line) 'face 'php-stack-current-source-line-highlight-face 'php-stack-current-source t)
  (setf php-stack-current-source-line-buffer  (current-buffer)))

(defun window-infos ()
  ;; for all windows of the frame: (window buffer buffer-file-name)
  (mapcar #'(lambda (window) (let ((buffer (window-buffer window)))
                               (list window buffer (buffer-file-name buffer))))
          (window-list)))

(defun window-that-displays-buffer-in-current-frame (buffer)
  (let ((window-with-buffer (find-if #'(lambda (window-info) (eq buffer (second window-info))) (window-infos))))
    (when window-with-buffer
      (setq the-global-window-buffer window-with-buffer)
      (car window-with-buffer))))

(defun highlight-php-stack-info (stack-info)
  (let ((stack-info-window (window-that-displays-buffer-in-current-frame (stack-info-source-buffer stack-info))))
    (if stack-info-window
        (select-window stack-info-window)
      (switch-to-buffer-other-window (stack-info-source-buffer stack-info)))
    (ov-clear 'php-stack-highlight)
    (goto-char (stack-info-source-buffer-start-pos stack-info))
    (ov-set (ov-line) 'face 'php-stack-line-highlight-face 'php-stack-highlight t)
    (recenter)))
(defun current-frame-displays-file-p (file)
  (remove-if-not #'(lambda (window-info) (string= (third window-info) file)) (window-infos)))
(defun window-that-displays-file-in-current-frame (file)
  (let ((windows-with-file (current-frame-displays-file-p file)))
    (when windows-with-file
      (caar windows-with-file))))
(defun current-stack-info ()
  (aref (php-stack-file-infos) (php-stack-index)))
(defun visit-current-php-stack-file (highlight-stack-p)
  (let ((current-stack-info (current-stack-info)))
    (let ((file (stack-info-file current-stack-info)))
      (when file
        (if (current-frame-displays-file-p file)
            (let ((the-window (window-that-displays-file-in-current-frame file)))
              (select-window the-window))
          (if (eq (current-buffer) (stack-info-source-buffer current-stack-info))
              (find-file-other-window file)
            (find-file file)))
        (let ((line (stack-info-line current-stack-info)))
          (when line
            (goto-line line)
            (highlight-this-line-as-current-source-line)
            (recenter)))))
    (when highlight-stack-p
      (highlight-php-stack-info current-stack-info))))

(defun start-php-stack-browse ()
  "start browsing the call stack which is under the cursor"
  (interactive)
  (get-stack-info-at-point)
  (visit-current-php-stack-file t))

(defun wait-until-seeing (yes no)
  (let (found
        (count 0))
    (while (not found)
      (sleep-for 0 100)
      (goto-char (point-max))
      (backward-char)
      (goto-char (point-at-bol))
      (message (format "waiting:%d" count))
      (incf count)
      ;; (when (looking-at "vagrant@homestead")
      ;;   (comint-goto-process-mark)
      ;;   (error "exited..."))
      (setf found (and (not (looking-at no)) (looking-at yes))))))

(defun trace-and-start-php-stack-browse ()
  (interactive)
  (jump-to-php-shell)
  (cond ((php-result-has-exception)
         (comint-send-string (get-buffer-process (current-buffer)) "$result->exception->getTraceAsString()\n\n")
         (wait-until-seeing ">>> " ">>> $result->exception->getTraceAsString()")
         (find-previous-stack-info-top))
        ((and (has-local-variable "$result")
              (php-expr-p "!is_null($result->original) &&
                           array_has($result->original, 'error') &&
                           is_array($result->original['error']) &&
                           count($result->original['error']) > 4"))
         (comint-send-string (get-buffer-process (current-buffer)) "$result->original['error'][4]->getTraceAsString()\n\n")
         (wait-until-seeing ">>> " ">>> $result->original")
         (find-previous-stack-info-top))
        (t
         (comint-send-string (get-buffer-process (current-buffer)) "trace\n\n")
         (wait-until-seeing ">>> " ">>> trace")
         (find-previous-stack-info-top))))

(defun jump-to-php-shell ()
  (interactive)
  (unless (in-php-shell-buffer-p)
    (setf saved-buffer-before-php-shell (current-buffer)))
  (let ((php-shell-buffer (cond ((and php-stack-data
                                      (php-stack-file-infos)
                                      (> (length (cdr php-stack-data)) 0))
                                 (stack-info-source-buffer (aref (php-stack-file-infos) 0)))
                                (php-shell-buffer php-shell-buffer))))
    (if php-shell-buffer
        (progn
          (unless (eq php-shell-buffer (current-buffer))
            (switch-to-buffer-other-window php-shell-buffer))
          (comint-goto-process-mark))
      (message "Sorry, I don't know which php-shell-buffer contains the php shell..."))))

(defun restore-saved-buffer-before-php-shell ()
  (interactive)
  (when saved-buffer-before-php-shell
    (switch-to-buffer-other-window saved-buffer-before-php-shell)))

(defun in-php-buffer-p ()
  (and (buffer-file-name)
       (string= (file-name-extension (buffer-file-name)) "php")))

(defun maybe-save-this-php-buffer ()
  (when (in-php-buffer-p)
    (save-buffer)))

(defun in-php-shell-buffer-p ()
  (eq (current-buffer) php-shell-buffer))

(defun maybe-interrupt-current-psysh-session ()
  (let (in-psysh-p)
    (save-excursion
      (backward-char)
      (goto-char (point-at-bol))
      (setf in-psysh-p (looking-at ">>>")))
    (when in-psysh-p
      (comint-send-string (get-buffer-process (current-buffer)) "\n"))))

(defun wait-for-new-psysh-or-bash-prompt (current-prompt)
  (wait-until-seeing (concatenate 'string "\\(>>> \\)\\|\\(" remote-shell-rx "\\)") current-prompt))

(defun rerun-last-phpunit-test (prefix)
  (interactive "p")
  (maybe-save-this-php-buffer)
  (jump-to-php-shell)
  (comint-clear-buffer)
  (maybe-interrupt-current-psysh-session)
  (let ((last-kbd-macro [?\M-r ?p ?h ?p ?u ?n ?i ?t return return]))
    (call-last-kbd-macro))
  (when t ;; I wanted to automatically go to the breakpoint, but I figured out I should be using process filters to do this waiting, tbd later
    (wait-for-new-psysh-or-bash-prompt (concatenate 'string remote-shell-rx "@.+\\$ vendor/bin"))
    (comint-goto-process-mark)
    (let ((action (save-excursion
                    (full-previous-line)
                    (cond ((looking-at ">>> ")
                           'psysh)
                          ((looking-at remote-shell-rx)
                           'bash)))))
      (cond ((eq action 'psysh)
             (message "psysh")
             (find-previous-stack-info-top)
             (when (and (= prefix 4))
               (cond  ((php-result-has-no-exception)
                       (insert "$result->json()")
                       (comint-send-input))
                      ((php-result-has-exception)
                       (insert "$result->exception")
                       (comint-send-input)
                       (wait-until-seeing ">>> " ">>> $result->exception")
                       (trace-and-start-php-stack-browse)))))
            ((eq action 'bash)
             (clear-current-stack-line-highlight)
             (message "test completed"))))
    (comint-goto-process-mark)))

(defun in-php-test-buffer-p ()
  (and (in-php-buffer-p)
       (string-match-p "tests/Feature/$" (file-name-directory (buffer-file-name)))))

(defun run-this-phpunit-test (prefix)
  (interactive "p")
  (let ((maybe-function-name (when (= 4 prefix)
                               (get-current-php-function-name))))
    (if (in-php-test-buffer-p)
        (let ((test-filename (file-name-nondirectory (buffer-file-name))))
          (maybe-save-this-php-buffer)
          (jump-to-php-shell)
          (comint-clear-buffer)
          (maybe-interrupt-current-psysh-session)
          (let ((maybe-filter (if maybe-function-name
                                  (concatenate 'string " --filter " maybe-function-name)
                                "")))
            (insert (concatenate 'string "vendor/bin/phpunit --no-coverage tests/Feature/" test-filename maybe-filter))
            (comint-send-input)))
      (message "This doesn't look like a php test"))))

(defun get-current-php-function-name ()
  (when (in-php-buffer-p)
    (save-excursion
      (php-beginning-of-defun)
      (let ((function-line-re " *\\(static\\)* *\\(\\(public\\)\\|\\(protected\\)\\|\\(private\\)\\) * \\(function\\) *\\([a-zA-Z0-9]+\\)"))
        (when (looking-at function-line-re)
          (let ((line (current-line)))
            (string-match function-line-re line)
            (match-string 7 line)))))))

(defun run-this-phpunit-test-or-return-to-test-buffer (prefix)
  (interactive "p")
  (if (in-php-shell-buffer-p)
      (restore-saved-buffer-before-php-shell)
    (run-this-phpunit-test prefix)))

(defun window-for-buffer-in-current-frame (buffer)
  (let* ((current-frame (window-frame (get-buffer-window (current-buffer))))
         (buffer-windows (get-buffer-window-list buffer))
         (windows-for-buffer-in-current-frame
          (remove-if-not #'(lambda (window) (eq current-frame (window-frame window))) buffer-windows)))
    (car windows-for-buffer-in-current-frame)))

(defun go-to-next-breakpoint ()
  (interactive)
  (jump-to-php-shell)
  (insert "")
  (comint-send-input)
  (wait-for-new-psysh-or-bash-prompt ">>> ")
  (find-previous-stack-info-top)
  (jump-to-php-shell
                    )
  (execute-php-command "$sql")
  )

(defmacro with-invisible-output (&rest body)
  `(progn
    (jump-to-php-shell)
    (let ((previous-prompt-point (point)))
      (unwind-protect
          (progn
            ,@body)
        (delete-region previous-prompt-point (point))))))

(defun execute-php-command (command)
  (insert command)
  (comint-send-input)
  (wait-until-seeing ">>> " (concatenate 'string ">>> " command))
  (comint-goto-process-mark))

(defun has-local-variable (variable-name)
  (with-invisible-output
   (comint-goto-process-mark)
   (execute-php-command "ls")
   (save-excursion
     (full-previous-line)
     (full-previous-line)
     (let ((local-variables (s-split ", " (substring (current-line) 11))))
       (if (not (null (member variable-name local-variables)))
           (message "yes!")
         (message "no:("))))))

(defun php-expr-p (expr)
  (with-invisible-output
   (comint-goto-process-mark)
   (execute-php-command expr)
   (save-excursion
     (full-previous-line)
     (full-previous-line)
     (looking-at "=> true"))))

(defun php-result-has-exception ()
  (and (has-local-variable "$result")
       (php-expr-p "!is_null($result->exception)")))

(defun php-result-has-no-exception ()
  (and (has-local-variable "$result")
       (php-expr-p "is_null($result->exception)")))

(defun go-to-current-breakpoint-buffer ()
  (interactive)
  (visit-current-php-stack-file nil))

(defun php-to-array ()
  (interactive)
  (when (in-php-shell-buffer-p)
    (execute-php-command "if (array_search('toArray', get_class_methods($_)) != false) { $_->toArray(); } else if (array_search('toJson', get_class_methods($_)) != false ) { $_->toJson(); } else if (array_search('json', get_class_methods($_)) != false) { $_->json(); } else {'huh? ';}")))

(global-set-key (kbd "<C-f10>") 'go-to-current-breakpoint-buffer)
(global-set-key (kbd "<C-f11>") 'highlight-previous-php-stack-entry)
(global-set-key (kbd "<C-f12>") 'highlight-next-php-stack-entry)
(global-set-key (kbd "<C-f9>") 'find-previous-stack-info-top)
(global-set-key (kbd "<C-f8>") 'trace-and-start-php-stack-browse)
(global-set-key (kbd "<C-f7>") 'jump-to-php-shell)
(global-set-key (kbd "<C-f6>") 'rerun-last-phpunit-test)
(global-set-key (kbd "<C-f5>") 'run-this-phpunit-test-or-return-to-test-buffer)
(global-set-key (kbd "<f9>") 'go-to-next-breakpoint)
(global-set-key (kbd "<C-return>") 'php-to-array)
(defface php-stack-line-highlight-face
  '((t :foreground "black"
       :background "aquamarine"
       :weight bold))
  "Face for php stack line in source buffer highlight.")

(defface php-stack-current-source-line-highlight-face
  '((t :foreground "black"
       :background "orange"
       :weight bold))
  "Face for php stack current source line highlight.")
