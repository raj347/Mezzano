(defpackage #:peek
  (:use #:cl))

(in-package #:peek)

(defclass peek-window (sys.graphics::text-window)
  ((process :reader window-process)))

(defmethod initialize-instance :after ((instance peek-window))
  (let ((process (make-instance 'sys.int::process :name "Peek")))
    (setf (slot-value instance 'process) process)
    (sys.int::process-preset process 'peek-top-level instance)
    (sys.int::process-enable process)))

(defun clear-window (window &optional (colour :black))
  (let* ((fb (sys.graphics::window-frontbuffer window))
         (dims (array-dimensions fb)))
    (sys.graphics::bitset (first dims) (second dims) (sys.graphics::make-colour colour) fb 0 0)
    (sys.int::stream-move-to window 0 0)
    (setf sys.graphics::*refresh-required* t)))

(defvar *peek-commands*
  '((#\? "Help" peek-help "Show a help page.")
    (#\P "Process" peek-process "Show currently active processes.")
    (#\M "Memory" peek-memory "Show memory information.")
    (#\N "Network" peek-network "Show network information.")
    (#\Q "Quit" nil "Quit Peek")))

(defun print-header ()
  (dolist (cmd *peek-commands*)
    (write-string (second cmd))
    (unless (char-equal (char (second cmd) 0) (first cmd))
      (format t "(~S)" (first cmd)))
    (write-char #\Space)))

(defun peek-help ()
  (format t "      Peek help~%")
  (format t "Char   Command   Info~%")
  (dolist (cmd *peek-commands*)
    (format t "~S ~A ~A~%" (first cmd) (second cmd) (fourth cmd))))

(defun peek-process ()
  (dolist (process sys.int::*active-processes*)
    (format t " ~A  ~A~%" (sys.int::process-name process) (sys.int::process-whostate process))))

(defun peek-memory ()
  (room))

(defun peek-network ()
  (format t "Network cards:~%")
  (dolist (card sys.net::*cards*)
    (let ((address (sys.net::ipv4-interface-address card)))
      (format t " ~S~%" card)
      (when address
        (format t "   IPv4 address: ~/sys.net::format-tcp4-address/~%" address))))
  (format t "Routing table:~%")
  (format t " Network Gateway Netmask Interface~%")
  (dolist (route sys.net::*routing-table*)
    (write-char #\Space)
    (if (first route)
        (sys.net::format-tcp4-address *standard-output* (first route))
        (write-string ":DEFAULT"))
    (write-char #\Space)
    (if (second route)
        (sys.net::format-tcp4-address *standard-output* (second route))
        (write-string "N/A"))
    (format t " ~/sys.net::format-tcp4-address/ ~S~%" (third route) (fourth route)))
  (format t "Servers:~%")
  (dolist (server sys.net::*server-alist*)
    (format t "~S  TCPv4 ~D~%" (second server) (first server)))
  (format t "TCPv4 connections:~%")
  (format t " Local       Remote        State~%")
  (dolist (conn sys.net::*tcp-connections*)
    (format t " ~D    ~/sys.net::format-tcp4-address/:~D  ~S~%"
            (sys.net::tcp-connection-local-port conn)
            (sys.net::tcp-connection-remote-ip conn) (sys.net::tcp-connection-remote-port conn)
            (sys.net::tcp-connection-state conn))))

(defun peek-top-level (window)
  (unwind-protect
       (sys.graphics::with-window-streams window
         (let ((mode 'peek-help))
           (loop
              (clear-window window)
              (print-header)
              (fresh-line)
              (funcall mode)
              (setf sys.graphics::*refresh-required* t)
              (let* ((ch (read-char window))
                     (cmd (assoc ch *peek-commands* :test 'char-equal)))
                (cond ((char= ch #\Space)) ; refresh current window
                      ((char-equal ch #\Q)
                       (return))
                      (cmd (setf mode (third cmd))))))))
    (sys.graphics::close-window window)))

(defun create-peek-window ()
  (sys.graphics::window-set-visibility (sys.graphics::make-window "Peek" 640 640 'peek-window) t))

(setf (gethash (name-char "F4") sys.graphics::*global-keybindings*) 'create-peek-window)