### =========================================================================
### RealizationSink objects
### -------------------------------------------------------------------------
###

### Virtual class with no slots. Intended to be extended by implementations
### of DelayedArray backends. Concrete subclasses must implement:
###   1) A constructor function that takes argument 'dim', 'dimnames', and
###      'type'.
###   2) A "dim", "dimnames", and "type" method.
###   3) A "write_block" method.
###   4) A "close" method (optional).
###   5) Coercion to DelayedArray.
###
### Examples of RealizationSink concrete subclasses: arrayRealizationSink
### (see below), RleRealizationSink (see RleArray-class.R),
### HDF5RealizationSink and TENxRealizationSink (see HDF5Array package).

setClass("RealizationSink", representation("VIRTUAL"))

setGeneric("close")

### The default "close" method for RealizationSink objects is a no-op.
setMethod("close", "RealizationSink", function(con) invisible(NULL))


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### arrayRealizationSink objects
###
### The arrayRealizationSink class is a concrete RealizationSink subclass that
### implements an in-memory realization sink.
###

setClass("arrayRealizationSink",
    contains="RealizationSink",
    representation(
        result_envir="environment"
    )
)

.get_arrayRealizationSink_result <- function(sink)
{
    get("result", envir=sink@result_envir)
}

.set_arrayRealizationSink_result <- function(sink, result)
{
    assign("result", result, envir=sink@result_envir)
}

setMethod("dim", "arrayRealizationSink",
    function(x) dim(.get_arrayRealizationSink_result(x))
)

arrayRealizationSink <- function(dim, dimnames=NULL, type="double")
{
    result <- array(get(type)(0), dim=dim, dimnames=dimnames)
    result_envir <- new.env(parent=emptyenv())
    sink <- new("arrayRealizationSink", result_envir=result_envir)
    .set_arrayRealizationSink_result(sink, result)
    sink
}

setMethod("write_block", "arrayRealizationSink",
    function(x, viewport, block)
    {
        result <- .get_arrayRealizationSink_result(x)
        result <- write_block(result, viewport, block)
        .set_arrayRealizationSink_result(x, result)
    }
)

setAs("arrayRealizationSink", "DelayedArray",
    function(from) DelayedArray(.get_arrayRealizationSink_result(from))
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Get/set the "realization backend" for the current session
###

.realization_backend_envir <- new.env(parent=emptyenv())

getRealizationBackend <- function()
{
    BACKEND <- try(get("BACKEND", envir=.realization_backend_envir),
                   silent=TRUE)
    if (is(BACKEND, "try-error"))
        return(NULL)
    BACKEND
}

.SUPPORTED_REALIZATION_BACKENDS <- data.frame(
    BACKEND=c("RleArray", "HDF5Array", "TENxMatrix"),
    package=c("DelayedArray", "HDF5Array", "HDF5Array"),
    realization_sink_class=c("RleRealizationSink", "HDF5RealizationSink", "TENxRealizationSink"),
    stringsAsFactors=FALSE
)

supportedRealizationBackends <- function()
{
    ans <- .SUPPORTED_REALIZATION_BACKENDS[ , c("BACKEND", "package")]
    backend <- getRealizationBackend()
    Lcol <- ifelse(ans[ , "BACKEND"] %in% backend, "->", "")
    Rcol <- ifelse(ans[ , "BACKEND"] %in% backend, "<-", "")
    cbind(data.frame(` `=Lcol, check.names=FALSE),
          ans,
          data.frame(` `=Rcol, check.names=FALSE))
}

### NOT exported.
load_BACKEND_package <- function(BACKEND)
{
    if (!isSingleString(BACKEND))
        stop(wmsg("'BACKEND' must be a single string or NULL"))
    backends <- .SUPPORTED_REALIZATION_BACKENDS
    m <- match(BACKEND, backends[ , "BACKEND"])
    if (is.na(m))
        stop(wmsg("\"", BACKEND, "\" is not a supported backend. Please ",
                  "use supportedRealizationBackends() to get the list of ",
                  "supported \"realization backends\"."))
    package <- backends[ , "package"][[m]]
    class_package <- attr(BACKEND, "package")
    if (is.null(class_package)) {
        attr(BACKEND, "package") <- package
    } else if (!identical(package, class_package)) {
        stop(wmsg("\"package\" attribute on supplied 'BACKEND' is ",
                  "inconsistent with package normally associated with ",
                  "this backend"))
    }
    library(package, character.only=TRUE)
    stopifnot(getClass(BACKEND)@package == package)
}

.get_REALIZATION_SINK_CONSTRUCTOR <- function(BACKEND)
{
    backends <- .SUPPORTED_REALIZATION_BACKENDS
    m <- match(BACKEND, backends[ , "BACKEND"])
    realization_sink_class <- backends[ , "realization_sink_class"][[m]]
    package <- backends[ , "package"][[m]]
    REALIZATION_SINK_CONSTRUCTOR <- get(realization_sink_class,
                                        envir=.getNamespace(package),
                                        inherits=FALSE)
    stopifnot(is.function(REALIZATION_SINK_CONSTRUCTOR))
    stopifnot(identical(head(formalArgs(REALIZATION_SINK_CONSTRUCTOR), n=3L),
                        c("dim", "dimnames", "type")))
    REALIZATION_SINK_CONSTRUCTOR
}

setRealizationBackend <- function(BACKEND=NULL)
{
    if (is.null(BACKEND)) {
        remove(list=ls(envir=.realization_backend_envir),
               envir=.realization_backend_envir)
        return(invisible(NULL))
    }
    load_BACKEND_package(BACKEND)
    REALIZATION_SINK_CONSTRUCTOR <- .get_REALIZATION_SINK_CONSTRUCTOR(BACKEND)
    assign("BACKEND", BACKEND,
           envir=.realization_backend_envir)
    assign("REALIZATION_SINK_CONSTRUCTOR", REALIZATION_SINK_CONSTRUCTOR,
           envir=.realization_backend_envir)
    return(invisible(NULL))
}


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Backend-agnostic RealizationSink constructor
###

.get_realization_sink_constructor <- function()
{
    if (is.null(getRealizationBackend()))
        return(arrayRealizationSink)
    REALIZATION_SINK_CONSTRUCTOR <- try(get("REALIZATION_SINK_CONSTRUCTOR",
                                            envir=.realization_backend_envir),
                                        silent=TRUE)
    if (is(REALIZATION_SINK_CONSTRUCTOR, "try-error"))
        stop(wmsg("This operation requires a \"realization backend\". ",
                  "Please see '?setRealizationBackend' for how to set one."))
    REALIZATION_SINK_CONSTRUCTOR
}

RealizationSink <- function(dim, dimnames=NULL, type="double")
{
    .get_realization_sink_constructor()(dim, dimnames, type)
}

