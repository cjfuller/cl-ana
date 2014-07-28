(in-package :makeres-table)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defvar *proj->tab->lfields*
    (make-hash-table :test 'equal)
    "Map from table id to any lfields defined via deflfields."))

;; logical field definition:
(defmacro deflfields (table-id lfields)
  "Sets logical fields for table-id; can be referenced via field by
any reductions of the table."
  (when (not (gethash *project-id* *proj->tab->lfields*))
    (setf (gethash *project-id* *proj->tab->lfields*)
          (make-hash-table :test 'equal)))
  (setf (gethash table-id
                 (gethash *project-id*
                          *proj->tab->lfields*))
        lfields)
  nil)

;; General table reduction:
(defmacro dotab (source-table init-bindings return &body body)
  "Operator used for denoting a loop over a table.

init-bindings are placed in a let* outside the loop body, which
executes body once per row in a context where the macro field is
defined which has access to any physical or logical fields by their
symbol.

return is the return value of the dotab, executed inside the
init-bindings let form."
  `(table-pass ,source-table ,init-bindings ,return () ,@body))

;; Physical table reductions:
(defmacro tab (source inits opener
               &body body)
  "Operator for generating physical tables via table-pass.  Returns a
table-pass form (so you can run macroexpand on it in a graph
transformation).

source is the source table to be iterated over.

opener should be a closure which accepts a single keyword argument.
When given keyword argument :read it should return an open table
object ready for reading, and when given keyword argument :write
should return a table object ready for writing.  opener should handle
all necessary calls to table-close as well as managing e.g. open
files.

inits are used for bindings outside the table-pass loop.

body will be placed in a macrolet which macrolets push-field,
accepting all arguments to table-push-field minus the destination
table (will be supplied the result table)."
  (let ((closure (gsym 'tabletrans))
        (result (gsym 'tabletrans)))
    `(table-pass ,source
         (,@inits
          (,closure ,opener)
          (,result (funcall ,closure :write)))
         (funcall ,closure :read)
         ()
       (macrolet ((push-fields (&rest fields)
                    `(table-push-fields ,',result
                       ,@fields)))
         ,@body))))

;; Logical table reductions:
(defmacro ltab (source inits &body body)
  "Like tab, but for logical tables.  Returns nil.  Requires special
  treatment since logical tables don't yield a result.  Arguments are
  simply for tracking the logical table."
  nil)

;;;; NOTES
;;;;
;;;; * The lfields argument is necessary in the way the merge
;;;;   algorithm is currently written.  There is however latent
;;;;   functionality which allows for individual table-pass form
;;;;   specific lfields in the algorithm which is unavailable to the
;;;;   user if they use the dotab operator; it is not a loss due to
;;;;   being able to use the let operator in the loop body, but this
;;;;   note is for future reference if concerns about lfields arise.

;; general purpose table iteration, more functional than do-table,
;; used as implementation backbone for all makeres-table
;; transformations
(defmacro table-pass (table inits result lfields &body body)
  "Loops over table with external bindings inits and result form
result, executing body once per row.

macro field yields the field value of current row.

macro row-number yields the row number of current row.

Limitations: Make sure no forms (field X) occur which are not meant to
reference the field value.  I've tried various options to make this
work via macros but nothing short of code walking looks viable, and
this is my naive code walking strategy's fault.

When used with makeres, each table-pass is guaranteed to have
independent lfields and inits, no matter what symbol names you choose.
If you need a common lfield, use deflfields.  If you need a common
init binding, at the moment the only solution is to combine the
targets manually (usually more conceptually clear incidentally)."
  ;; local macro fields will accept either symbol or string, and will
  ;; convert a symbol into a lower-case string for use in fields.

  ;; Having difficulties expanding the body to get the fields which
  ;; are present, trying to use &environment with expand macro but not
  ;; much luck so far.
  (let ((lfield->gsym
         (let ((result (make-hash-table :test 'equal)))
           (loop for i in lfields
              do (setf (gethash (first i) result)
                       (gsym 'tabletrans)))
           result)))
    (let ((ri (gsym 'tabletrans)))
      `(macrolet ((field (field-sym)
                    (or (gethash field-sym ,lfield->gsym)
                        (intern (lispify field-sym)))))
         (let* ,inits
           (do-table (,ri ,table)
               ,(list->set (mapcar (lambda (x)
                                     (if (symbolp x)
                                         (intern (lispify x))
                                         (string x)))
                                   (remove-if
                                    (lambda (x)
                                      (gethash x lfield->gsym))
                                    (append (makeres::find-dependencies lfields 'field)
                                            (makeres::find-dependencies body 'field))))
                           #'string=)
             (olet ,(loop for i in lfields
                       collect `(,(gethash (first i) lfield->gsym)
                                  ,(second i)))
               ,@(remove-if-not (lambda (x)
                                  (and (listp x)
                                       (eq (first x)
                                           'declare)))
                                body)
               (flet ((row-number ()
                        ,ri))
                 ,@(remove-if (lambda (x)
                                (and (listp x)
                                     (eq (first x)
                                         'declare)))
                              body))))
           ,result)))))
