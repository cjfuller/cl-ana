;;;; logres is a Common Lisp make-like tool for computations.
;;;; Copyright 2014 Gary Hollis
;;;; 
;;;; This file is part of logres.
;;;; 
;;;; logres is free software: you can redistribute it and/or modify it
;;;; under the terms of the GNU General Public License as published by
;;;; the Free Software Foundation, either version 3 of the License, or
;;;; (at your option) any later version.
;;;; 
;;;; logres is distributed in the hope that it will be useful, but
;;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;;; General Public License for more details.
;;;; 
;;;; You should have received a copy of the GNU General Public License
;;;; along with logres.  If not, see <http://www.gnu.org/licenses/>.
;;;;
;;;; You may contact Gary Hollis via email at
;;;; ghollisjr@gmail.com

(defsystem #:cl-ana.logres
  :serial t
  :author "Gary Hollis"
  :description "logres is a result logging (storage and retrieval tool
  for use with makeres"
  :license "GPLv3"
  :depends-on (#:external-program
               #:cl-ana.hdf-utils
               #:cl-ana.serialization
               #:cl-ana.map
               #:cl-ana.string-utils
               #:cl-ana.functional-utils
               #:cl-ana.file-utils
               #:cl-ana.histogram
               #:cl-ana.pathname-utils
               #:cl-ana.table
               #:cl-ana.reusable-table
               #:cl-ana.makeres)
  :components ((:file "package")
               (:file "logres")
               (:file "histogram")
               (:file "table")
               (:file "function")
               (:file "hash-table")
               (:file "cons")
               (:file "array")
               (:file "string")))
