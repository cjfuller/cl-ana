;;;; plotting.lisp

;;;; This library provides access to gnuplot from CL via
;;;; gnuplot-i-cffi, which in turn uses gnuplot_i (see
;;;; gnuplot-i-cffi's files for appropriate copyright info).
;;;;
;;;; The structure of the classes follows gnuplot, with the exception
;;;; of the plot/graph distinction being seen as unnecessary.
;;;;
;;;; The structure is as follows:
;;;;
;;;; Page: The most basic thing which can be plotted upon.  Pages
;;;; contain some number of plots which are drawn on the page.
;;;;
;;;; Plot: A plot is either 2-D or 3-D, and defines the appropriate
;;;; axis.  A plot contains some number of lines which are drawn
;;;; together in the plot.
;;;;
;;;; Line: A line is a single function or collection of data which can
;;;; be plotted inside of a plot.
;;;;
;;;; There are a couple of convenience generic functions for plotting:
;;;; quick-draw and make-line.
;;;;
;;;; quick-draw is for quickly drawing some object in graphical form.
;;;;
;;;; make-line is for generating a line representing some object.
;;;;
;;;; quick-draw by the default method creates a 2-D plot using
;;;; make-line on the object, which means that in most cases all you
;;;; have to do is define a method of make-line for your type and you
;;;; can already use quick-draw.
;;;;
;;;; test.lisp demonstrates an example of using the full structure for
;;;; creating more complex plots; one can presumably define his own
;;;; functions for generating complex plots with certain conventions.
;;;; However I do intend to write a few convenience functions for
;;;; this, perhaps using plists to denote the structure of the
;;;; plotting objects.

(in-package :plotting)

(defvar *gnuplot-session* (gnuplot-init))

;; run any initialization functions:
(defun gnuplot-settings ()
  (gnuplot-cmd *gnuplot-session* "set palette rgb 33,13,10"))

(gnuplot-settings)

(defun restart-gnuplot-session ()
  (gnuplot-close *gnuplot-session*)
  (setf *gnuplot-session* (gnuplot-init))
  (gnuplot-settings))

(defgeneric generate-cmd (object)
  (:documentation "Generates a command string (with new-line at end)
  for drawing a particular element.  Assumes that the appropriate
  context has been set up by the page/draw function."))

(defclass titled ()
  ((title
    :initarg :title
    :initform ""
    :accessor title
    :documentation "Gnuplot likes to name everything with what it
    calls a title, so I've created a base class for this
    functionality.")))

;; A page is a whole window, sheet of paper, etc.  It can contain
;; multiple plots/graphs.
(defclass page (titled)
  ((next-id
    :initform 0
    :documentation "The next available id for a page."
    :reader page-next-id
    :allocation :class)
   (id
    ;;:initarg :id
    :initform -1
    :reader page-id
    :documentation "The numerical id of the page; necessary for
    gnuplot to know to create a distinct page rather than reuse the
    last one used.")
   ;;; actually set-able slots:
   (shown-title
    :initform nil
    :initarg :shown-title
    :accessor page-shown-title
    :documentation "Since I implement the plotting with multiplot in
    gnuplot, there is the possibility of the page having a title as
    well as the plots having a collective title.  This sets the shown
    title.")
   (dimensions
    :initform nil
    :initarg :dimensions
    :accessor page-dimensions
    :documentation "A cons pair (width . height) in pixels for the
    page size.")
   (scale
    :initform (cons 1 1)
    :initarg :scale
    :accessor page-scale
    :documentation "A cons pair (x-scale . y-scale) denoting the scale
    for each plot.")
   (plots
    :initarg :plots
    :initform ()
    :accessor page-plots
    :documentation "The list of plots which are currently part of the
    page.")
   (layout
    :initarg :layout
    :initform (cons 1 1)
    :accessor page-layout
    :documentation "A cons (numrows . numcols) telling how to arrange
    the plots in the multiplot.")
   (type
    :initarg :type
    :initform "wxt"
    :accessor page-type
    :documentation "The type of page, gnuplot only supports a fixed
    number of types so this makes more sense to be added as a slot
    then to have different page types.")))

(defgeneric page-add-plot (page plot)
  (:documentation "Adds a plot to the page.")
  (:method (page plot)
    (push plot (page-plots page))))

(defmethod generate-cmd ((p page))
  (with-accessors ((title title)
                   (shown-title page-shown-title)
                   (id page-id)
                   (type page-type)
                   (layout page-layout)
                   (dimensions page-dimensions)
                   (scale page-scale)
                   (plots page-plots))
      p
    (string-append
     (with-output-to-string (s)
       (format s "set term ~a ~a title '~a'" type id title)
       (when dimensions
         (format s " size ~a,~a" (car dimensions) (cdr dimensions)))
       (format s "~%")
       (format s "set multiplot layout ~a,~a title '~a'"
               (car layout) (cdr layout)
               (if shown-title
                   shown-title
                   ""))
       (when scale
         (format s "scale ~a,~a" (car scale) (cdr scale)))
       (format s "~%"))
     (reduce #'string-append
             (loop
                for plot in plots
                collecting (generate-cmd plot)))
     "unset multiplot")))

(defun draw (page)
  "Draws the contents of a page using the multiplot layout specified
in the page."
  (gnuplot-cmd *gnuplot-session* (generate-cmd page)))

(defmethod initialize-instance :after
  ((p page) &key)
  (incf (slot-value p 'next-id)))

(defmethod initialize-instance ((p page)
                                &key id
                                  &allow-other-keys)
  (let ((next-id (slot-value p 'next-id)))
    (when (not id)
      (setf (slot-value p 'id) next-id)))
  (call-next-method))

;; A plot is defined by an abscissa and an ordinate, though these
;; don't necessarily have to be drawn, as well as the margins and any
;; text written inside.  Each plot may contain one or more lines.
(defclass plot (titled)
  ((lines
    :initarg :lines
    :initform ()
    :accessor plot-lines
    :documentation "The lines which are part of the plot.")
   (legend
    :initarg :legend
    :initform nil
    :accessor plot-legend
    :documentation "The legend (if any) to be drawn on the plot.")))

(defgeneric plot-cmd (plot)
  (:documentation "The command used for plotting the plot in gnuplot;
  can be plot, splot, etc."))

(defmethod generate-cmd ((p plot))
  (with-accessors ((title title)
                   (lines plot-lines)
                   (legend plot-legend))
      p
    (with-output-to-string (s)
      (format s "set title '~a'~%" title)
      (format s "~a " (plot-cmd p))
      (loop
         for cons on lines
         do (format s "~a" (generate-cmd (car cons)))
         when (cdr cons)
         do (format s ", "))
      (format s "~%")
      (loop
         for l in lines
         do (format s "~a" (line-data-cmd l))))))

(defgeneric plot-add-line (plot line)
  (:documentation "Adds a line to the plot; usually updates the legend
  based on the legend's update strategy.")
  (:method (plot line)
    (with-accessors ((lines plot-lines)
                     (legend plot-legend))
        plot
      (push line lines)
      (setf legend
            (legend-update legend line)))))

;; A two-dimensional plot has up to four labelled axes:
;;
;; "x" for the axis along the bottom,
;; "y" for the axis along the left edge,
;; "x2" for the axis along the top, and
;; "y2" for the axis along the right edge.
(defclass plot2d (plot)
  ((x-range
    :initarg :x-range
    :initform nil
    :accessor plot2d-x-range
    :documentation "Sets the domain for the plot; a cons where the car
    is the lower bound and the cdr is the upper bound.")
   (y-range
    :initarg :y-range
    :initform nil
    :accessor plot2d-y-range
    :documentation "Sets the range for the plot; a cons where the car
    is the lower bound and the cdr is the upper bound.")))

(defmethod plot-cmd ((p plot2d))
  (with-slots (x-range y-range)
      p
    (with-output-to-string (s)
      (format s "plot ")
      (if x-range
          (format s "[~a:~a] "
                  (car x-range) (cdr x-range))
          (format s "[*:*] "))
      (when y-range
        (format s "[~a:~a] "
                (car y-range) (cdr y-range))
        (format s "[*:*] ")))))

;; A three dimensional plot has up to three labelled axes, "x", "y",
;; and "z".
(defclass plot3d (plot)
  ())

(defmethod plot-cmd ((p plot3d))
  "splot")

;; A line is a single function or data set.  Each line may have its
;; own individual name/title.  These may be listed together in a key or
;; legend.
(defclass line (titled)
  ((style
    :initform "lines"
    :initarg :style
    :accessor line-style
    :documentation "Plotting style.  Defaults to lines for ease of
    implemenation, users should change this if they want another
    style, like points.")
   (color
    :initform nil
    :initarg :color
    :accessor line-color
    :documentation "Color for plotting the line.")
   (plot-arg
    :initarg :plot-arg
    :initform ""
    :accessor line-plot-arg
    :documentation "The string denoting the plot argument which should
    directly proceed the plot/splot command; can be a function body,
    '-', or a file name.")
   (options
    :initarg :options
    :initform ""
    :accessor line-options
    :documentation "Miscellaneous options not covered by the standard
    ones above; this is to permit things like image plotting.")))

(defmethod line-data-cmd ((l line))
  "")

(defmethod generate-cmd ((l line))
  (with-output-to-string (s)
    (with-accessors ((title title)
                     (style line-style)
                     (plot-arg line-plot-arg)
                     (color line-color)
                     (options line-options))
        l
      (format s "~a with " plot-arg)
      (format s "~a " style)
      (format s "~a " options)
      (when color
        (format s "linecolor rgb '~a' " color))
      (format s "title '~a'" title))))

(defclass data-line (line)
  ((data
    :initarg :data
    :initform ()
    :accessor data-line-data
    :documentation "The individual data points to be plotted; can be
    2-D or 3-D, in either case the line-data is an alist mapping the
    independent value (or values as a list) to the dependent value.")))

(defmethod initialize-instance :after ((l data-line) &key)
  (setf (slot-value l 'plot-arg) "'-'"))

(defmethod line-data-cmd ((line data-line))
  (with-output-to-string (s)
    (with-accessors ((data data-line-data))
        line
      (let ((extractor
             (if data
                 (if (listp (car (first data)))
                     #'(lambda (cons)
                         (format s "~{~a ~}" (car cons))
                         (format s "~a~%" (cdr cons)))
                     #'(lambda (cons)
                         (format s "~a ~a~%"
                                 (car cons)
                                 (cdr cons))))
                 (error "Empty data in data-line"))))
        (loop
           for d in data
           do (funcall extractor d))
        (format s "e~%")))))

(defclass analytic-line (line)
  ((fn-string
    :initarg :fn-string
    :initform "0"
    :accessor analytic-line-fn-string
    :documentation "The function expression to plot, should be a
    function of x/x and y.")))

(defun analytic-line-set-plot-arg (line)
  (with-slots (x-range y-range fn-string)
      line
    (setf
     (slot-value line 'plot-arg)
     (with-output-to-string (s)
       (format s "~a " fn-string)))))

(defmethod initialize-instance :after ((l analytic-line) &key)
  (analytic-line-set-plot-arg l))

(defmethod (setf line-plot-arg) :after (value (l analytic-line))
  (analytic-line-set-plot-arg l))

(defclass legend ()
  ((contents
    :initform ""
    :initarg :contents
    :accessor legend-contents
    :documentation "The legend contents to be shown.")
   (update-strategy
    :initform #'identity
    :initarg :update-strategy
    :accessor legend-update-strategy
    :documentation "A function which updates the legend based on the
    addition of a line.  Could be simply add the title to the legend,
    or do nothing.  Strategy is functional, i.e. it should return a
    lew legend based on the old one and the new line, not actually
    change the state of the current legend.")))

(defgeneric legend-update (legend line)
  (:documentation "Updates the legend for the plot based on the
  legend's update strategy.")
  (:method (legend line)
    (with-accessors ((strategy legend-update-strategy))
        legend
      (setf legend
            (funcall strategy legend line)))))

;;; Convenience functions:

(defun quick-multidraw (object-specs &key
                                       (type "wxt")
                                       (page-title "")
                                       (shown-page-title "")
                                       (plot-title "")
                                       (x-title "x")
                                       (y-title "y"))
  "Plots objects all on one plot similarly to quick-draw but
  pluralized, as well as optionally giving each object's line a title.

  An object-spec is a list being the object to plot consed onto a
  plist specifying the keyword arguments to give to make-line."
  (let ((page
         (make-instance
          'page
          :title page-title
          :shown-title shown-page-title
          :type "wxt"
          :plots (list (make-instance
                        'plot2d
                        :title plot-title
                        :lines (mapcar
                                #'(lambda (object-spec)
                                    (apply #'make-line object-spec))
                                object-specs))))))
    (draw page)
    page))

(defgeneric make-line (object &key &allow-other-keys)
  (:documentation "Returns a line appropriate for plotting object."))

(defgeneric quick-draw (object &key &allow-other-keys)
  (:documentation "Returns a page which stores a single plot and
  single line as well as drawing the page.")
  ;; Default method for 2-D plotting
  (:method (object &key
                     (type "wxt")
                     (title "plot")
                     (x-title "x")
                     (y-title "y"))
    (let* ((line (make-line object))
           (page
            (make-instance
             'page
             :type type
             :plots (list (make-instance
                           'plot2d
                           :title title
                           :lines (list line))))))
      (draw page)
      page)))

;; analytic functions:
(defmethod make-line ((s string) &key
                                   (title "" title-given-p)
                                   color)
  (apply #'make-instance 'analytic-line
         :fn-string s
         :color color
         (if title-given-p
             (list :title title)
             (list :title s))))

;; data:
(defmethod make-line ((data-alist list) &key
                                          (title "data")
                                          (style "points")
                                          color)
  "Assumes"
  (make-instance 'data-line
                 :title title
                 :data data-alist
                 :style style
                 :color color))

;; functions:
(defmethod make-line ((fn function) &key
                                      (title "function")
                                      (style "lines")
                                      (lower-bounds -3d0)
                                      (upper-bounds 3d0)
                                      (samples 100)
                                      color)
  "Samples your function based on the keyword arguments and creates a
  data-line mapping your function to the output values.

Conventions are:

fn must evaluate to a float (single or double).

All bounds/samples arguments must be of the same type, and must be
either atoms or lists.

If the bounds/samples arguments are atoms, then fn is assumed to take
a single double-float argument.

If the bounds/samples are lists, then fn is assumed to take a list of
up to two double-float arguments."
  (let* (; taking advantage of the tensor functions:
         (deltas (/ (- upper-bounds lower-bounds)
                    (- samples 1)))
         (raw-domain
          (apply #'cartesian-product
                 (mapcar #'range
                         (mklist lower-bounds)
                         (mklist upper-bounds)
                         (mklist deltas))))
         (domain (if (atom deltas)
                     (first (transpose raw-domain))
                     raw-domain)))
    (make-line (zip domain (mapcar fn domain))
               :title title
               :style style
               :color color)))
;; histogram plotting:

;; still need to allow for error bars
(defmethod make-line ((hist histogram) &key
                                         (title "histogram")
                                         color)
  (let* ((ndims (hist-ndims hist))
         (bin-data (map->alist hist))
         (first-independent (car (first bin-data))))
    (case ndims
      (1
       (if (not (atom first-independent))
           (error "Must be 1-d independent variable")
           (make-instance 'data-line
                          :data bin-data
                          :style "boxes"
                          :color color)))
      (2 
       (if (or (not (consp first-independent))
               (not (length-equal first-independent 2)))
           (error "Must be 2-d independent variable")
           (make-instance 'data-line
                          :title title
                          :data bin-data
                          :style "image"
                          :color color)))
      (otherwise (error "Can only plot 1-D or 2-D histograms")))))
