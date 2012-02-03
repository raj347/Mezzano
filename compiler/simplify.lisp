;;;; Simplifiy the ast by removing empty nodes and unused variables.

(in-package #:system.compiler)

(defun simp-form (form)
  (etypecase form
    (cons (case (first form)
	    ((block) (simp-block form))
	    ((go) (simp-go form))
	    ((if) (simp-if form))
	    ((let) (simp-let form))
	    ((load-time-value) (simp-load-time-value form))
	    ((multiple-value-bind) (simp-multiple-value-bind form))
	    ((multiple-value-call) (simp-multiple-value-call form))
	    ((multiple-value-prog1) (simp-multiple-value-prog1 form))
	    ((progn) (simp-progn form))
	    ((progv) (simp-progv form))
	    ((quote) (simp-quote form))
	    ((return-from) (simp-return-from form))
	    ((setq) (simp-setq form))
	    ((tagbody) (simp-tagbody form))
	    ((the) (simp-the form))
	    ((unwind-protect) (simp-unwind-protect form))
	    (t (simp-function-form form))))
    (lexical-variable (simp-variable form))
    (lambda-information (simp-lambda form))))

(defun simp-implicit-progn (x &optional flatten)
  (do ((i x (cdr i)))
      ((endp i))
    ;; Merge nested PROGNs.
    (let ((form (car i)))
      (if (and flatten
	       (consp form)
	       (eq (car form) 'progn)
	       (cdr form))
	  (progn
	    (incf *change-count*)
	    (setf (car i) (simp-form (second form))
		  (cdr i) (nconc (cddr form) (cdr i))))
	  (setf (car i) (simp-form form))))))

(defun simp-block (form)
  (if (eql (lexical-variable-use-count (second form)) 0)
      (progn
	(incf *change-count*)
	(simp-form `(progn ,@(cddr form))))
      (progn
	(simp-implicit-progn (cddr form) t)
	form)))

(defun simp-go (form)
  form)

(defun simp-if (form)
  (setf (second form) (simp-form (second form))
	(third form) (simp-form (third form))
	(fourth form) (simp-form (fourth form)))
  form)

(defun simp-let (form)
  ;; Merge nested LETs when possible, do not merge special bindings!
  (do ((nested-form (caddr form) (caddr form)))
      ((or (not (consp nested-form))
	   (not (eq (first nested-form) 'let))
	   (and (second nested-form)
		(symbolp (first (second nested-form))))))
    (incf *change-count*)
    (if (null (second nested-form))
	(setf (cddr form) (nconc (cddr nested-form) (cdddr form)))
	(setf (second form) (nconc (second form) (list (first (second nested-form))))
	      (second nested-form) (rest (second nested-form)))))
  ;; Remove unused values with no side-effects.
  (setf (second form) (remove-if (lambda (b)
				   (let ((var (first b))
					 (val (second b)))
				     (and (lexical-variable-p var)
					  (or (lambda-information-p val)
					      (and (consp val) (eq (first val) 'quote))
					      (and (lexical-variable-p val)
						   (localp val)
						   (eql (lexical-variable-write-count val) 0)))
					  (eql (lexical-variable-use-count var) 0)
					  (progn (incf *change-count*)
						 (flush-form val)
						 t))))
				 (second form)))
  (dolist (b (second form))
    (setf (second b) (simp-form (second b))))
  ;; Remove the LET if there are no values.
  (if (second form)
      (progn
	(simp-implicit-progn (cddr form) t)
	form)
      (progn
	(incf *change-count*)
	(simp-form `(progn ,@(cddr form))))))

;;;(defun simp-load-time-value (form))

(defun simp-multiple-value-bind (form)
  ;; If no variables are used, or there are no variables then
  ;; remove the form.
  (cond ((every (lambda (var)
                  (and (lexical-variable-p var)
                       (zerop (lexical-variable-use-count var))))
                (second form))
         (incf *change-count*)
         (simp-form `(progn ,@(cddr form))))
        (t (simp-implicit-progn (cddr form) t)
           form)))

(defun simp-multiple-value-call (form)
  (simp-implicit-progn (cdr form))
  form)

(defun simp-multiple-value-prog1 (form)
  (setf (second form) (simp-form (second form)))
  (simp-implicit-progn (cddr form) t)
  form)

(defun simp-progn (form)
  (cond ((null (cdr form))
	 ;; Flush empty PROGNs.
	 (incf *change-count*)
	 ''nil)
	((null (cddr form))
	 ;; Reduce single form PROGNs.
	 (incf *change-count*)
	 (simp-form (second form)))
	(t (simp-implicit-progn (cdr form) t)
	   form)))

(defun simp-progv (form)
  (setf (second form) (simp-form (second form))
	(third form) (simp-form (third form)))
  (simp-implicit-progn (cdddr form) t)
  form)

(defun simp-quote (form)
  form)

(defun simp-return-from (form)
  (setf (third form) (simp-form (third form)))
  form)

(defun simp-setq (form)
  (setf (third form) (simp-form (third form)))
  form)

(defun simp-tagbody (form)
  (labels ((flatten (x)
	     (cond ((and (consp x)
			 (eq (car x) 'progn))
		    (incf *change-count*)
		    (apply #'nconc (mapcar #'flatten (cdr x))))
		   ((and (consp x)
			 (eq (car x) 'tagbody))
		    ;; Merge directly nested TAGBODY forms, dropping unused go tags.
		    (incf *change-count*)
		    (setf (tagbody-information-go-tags (second form))
			  (nconc (tagbody-information-go-tags (second form))
				 (delete-if (lambda (x) (eql (go-tag-use-count x) 0))
					    (tagbody-information-go-tags (second x)))))
		    (apply #'nconc (mapcar (lambda (x)
					     (if (go-tag-p x)
						 (unless (eql (go-tag-use-count x) 0)
						   (setf (go-tag-tagbody x) (second form))
						   (list x))
						 (flatten x)))
					   (cddr x))))
		   (t (cons (simp-form x) nil)))))
    (setf (tagbody-information-go-tags (second form))
	  (delete-if (lambda (x) (eql (go-tag-use-count x) 0))
		     (tagbody-information-go-tags (second form))))
    (do* ((i (cddr form) (cdr i))
	  (result (cdr form))
	  (tail result))
	 ((endp i))
      (let ((x (car i)))
	(if (go-tag-p x)
	    ;; Drop unused go tags.
	    (if (eql (go-tag-use-count x) 0)
		(incf *change-count*)
		(setf (cdr tail) (cons x nil)
		      tail (cdr tail)))
	    (setf (cdr tail) (flatten x)
		  tail (last tail)))))
    ;; Reduce tagbodys with no tags to progn.
    (cond ((tagbody-information-go-tags (second form))
	   form)
	  ((null (cddr form))
	   (incf *change-count*)
	   ''nil)
	  ((null (cdddr form))
	   (incf *change-count*)
	   (caddr form))
	  (t (incf *change-count*)
	     `(progn ,@(cddr form))))))

(defun simp-the (form)
  (cond ((eql (second form) 't)
         (incf *change-count*)
         (simp-form (third form)))
        (t (setf (third form) (simp-form (third form)))
           form)))

(defun simp-unwind-protect (form)
  (setf (second form) (simp-form (second form)))
  (simp-implicit-progn (cddr form) t)
  form)

(defun simp-function-form (form)
  ;; (funcall 'symbol ...) -> (symbol ...)
  (cond ((and (eql (first form) 'funcall)
              (listp (second form))
              (= (list-length (second form)) 2)
              (eql (first (second form)) 'quote)
              (symbolp (second (second form))))
         (incf *change-count*)
         (simp-implicit-progn (cddr form))
         (list* (second (second form)) (cddr form)))
        (t (simp-implicit-progn (cdr form))
           form)))

(defun simp-variable (form)
  form)

(defun simp-lambda (form)
  (let ((*current-lambda* form))
    (dolist (arg (lambda-information-optional-args form))
      (setf (second arg) (simp-form (second arg))))
    (dolist (arg (lambda-information-key-args form))
      (setf (second arg) (simp-form (second arg))))
    (simp-implicit-progn (lambda-information-body form) t))
  form)
