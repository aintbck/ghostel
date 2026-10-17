;;; ghostel-shell-command-test.el --- Tests for ghostel: shell-command -*- lexical-binding: t; -*-

;;; Commentary:

;; `ghostel-shell-command' and `ghostel-shell-command-global-mode'.

;;; Code:

(require 'ghostel-test-helpers)
(require 'ghostel-shell-command)

(ert-deftest ghostel-test-shell-command-uses-new-buffer-when-busy ()
  "`ghostel-shell-command' honours `async-shell-command-buffer' and the shell vars."
  (let* ((ghostel-shell-command-buffer-name " *ghostel-shell-command-test*")
         (busy (get-buffer-create ghostel-shell-command-buffer-name))
         (async-shell-command-buffer 'new-buffer)
         (shell-file-name "/bin/sh")
         (shell-command-switch "-c")
         captured result)
    (unwind-protect
        (progn
          (with-current-buffer busy
            (setq ghostel--process 'fake-process))
          (cl-letf (((symbol-function 'process-live-p)
                     (lambda (p) (eq p 'fake-process)))
                    ((symbol-function 'display-buffer) #'ignore)
                    ((symbol-function 'ghostel-exec)
                     (lambda (&rest args) (setq captured args) 'fake-proc)))
            (setq result (ghostel-shell-command "echo hi")))
          (should-not (eq result busy))
          (should (equal (cdr captured)
                         '("/bin/sh" ("-c" "echo hi")
                           ((kind . shell-command)
                            (command . ("/bin/sh" "-c" "echo hi"))))))
          (should-not (buffer-local-value 'ghostel-kill-buffer-on-exit result)))
      (kill-buffer busy)
      (when (buffer-live-p result) (kill-buffer result)))))

(ert-deftest ghostel-test-shell-command-strips-trailing-ampersand ()
  "A trailing & is dropped so the command runs in the foreground."
  (let ((ghostel-shell-command-buffer-name " *ghostel-shell-command-amp*")
        (shell-file-name "/bin/sh")
        (shell-command-switch "-c")
        captured result)
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'display-buffer) #'ignore)
                    ((symbol-function 'ghostel-exec)
                     (lambda (&rest args) (setq captured args) 'fake-proc)))
            (setq result (ghostel-shell-command "sleep 1 &")))
          (should (equal (nth 2 captured) '("-c" "sleep 1"))))
      (when (buffer-live-p result) (kill-buffer result)))))

(ert-deftest ghostel-test-shell-command-kill-policy-replaces-busy-buffer ()
  "`confirm-kill-process' asks once, ends the running command, reuses the name."
  :tags '(native)
  (skip-unless (not (ghostel-test--windows-p)))
  (let ((ghostel-shell-command-buffer-name " *ghostel-shell-command-kill*")
        (ghostel-detect-password-prompts nil)
        (ghostel-query-before-killing t)
        (async-shell-command-buffer 'confirm-kill-process)
        (shell-file-name "/bin/sh")
        (shell-command-switch "-c")
        (prompts 0))
    (ghostel-test--with-pty-matrix _backend
      (setq prompts 0)
      (let* ((busy (ghostel-shell-command "sleep 30"))
             (busy-proc (buffer-local-value 'ghostel--process busy))
             (fresh (cl-letf (((symbol-function 'yes-or-no-p)
                               (lambda (&rest _) (cl-incf prompts) t)))
                      (ghostel-shell-command "echo GHOSTEL_AFTER_KILL"))))
        (unwind-protect
            (progn
              (should (= prompts 1))
              (should-not (buffer-live-p busy))
              (should (equal (buffer-name fresh) ghostel-shell-command-buffer-name))
              (with-current-buffer fresh
                (ghostel-test--wait-for-text "GHOSTEL_AFTER_KILL" nil 5))
              (ghostel-test--wait-until
               (lambda () (not (process-live-p busy-proc))) nil 5))
          (when (buffer-live-p fresh) (kill-buffer fresh)))))))

(ert-deftest ghostel-test-shell-command-keeps-buffer-after-exit ()
  "`ghostel-shell-command' output stays readable after the command exits."
  :tags '(native)
  (skip-unless (not (ghostel-test--windows-p)))
  (let ((ghostel-shell-command-buffer-name " *ghostel-shell-command-test*")
        (ghostel-detect-password-prompts nil)
        (shell-file-name "/bin/sh")
        (shell-command-switch "-c"))
    (ghostel-test--with-pty-matrix _backend
      (let ((buf (ghostel-shell-command "echo GHOSTEL_SHELL_CMD_OUTPUT")))
        (unwind-protect
            (with-current-buffer buf
              (let ((proc ghostel--process))
                (ghostel-test--wait-for-text "GHOSTEL_SHELL_CMD_OUTPUT" nil 5)
                (ghostel-test--wait-until
                 (lambda () (not (process-live-p proc))) nil 5)
                (should (buffer-live-p buf))
                (should (string-match-p "GHOSTEL_SHELL_CMD_OUTPUT"
                                        (ghostel-test--terminal-text)))))
          (when (buffer-live-p buf) (kill-buffer buf)))))))

(ert-deftest ghostel-test-shell-command-rejects-empty-command ()
  "An empty command, or a lone &, signals `user-error'."
  (should-error (ghostel-shell-command "") :type 'user-error)
  (should-error (ghostel-shell-command " &") :type 'user-error))

(ert-deftest ghostel-test-shell-command-global-mode-routes-async-only ()
  "The global mode sends & commands to ghostel and leaves the rest alone."
  (let (ghostel-calls orig-calls)
    (cl-letf (((symbol-function 'ghostel-shell-command)
               (lambda (&rest args) (push args ghostel-calls)))
              ((symbol-function 'shell-command)
               (lambda (&rest args) (push args orig-calls))))
      (unwind-protect
          (progn
            (ghostel-shell-command-global-mode 1)
            (shell-command "sleep 1 &")
            (shell-command "ls")
            (shell-command "sleep 1 &" "*out*")
            (shell-command "sleep 1 &" (current-buffer))
            (shell-command "sleep 1 &" t)
            (ghostel-shell-command-global-mode -1)
            (shell-command "sleep 1 &"))
        (ghostel-shell-command-global-mode -1)))
    (should (equal (nreverse ghostel-calls)
                   '(("sleep 1 &" nil) ("sleep 1 &" "*out*"))))
    (should (equal (mapcar #'car (nreverse orig-calls))
                   '("ls" "sleep 1 &" "sleep 1 &" "sleep 1 &")))))

(provide 'ghostel-shell-command-test)

;;; ghostel-shell-command-test.el ends here
