\name{realize}

\alias{BLOCK_write_to_sink}

\alias{realize}
\alias{realize,ANY-method}

\title{Realize a DelayedArray object}

\description{
  Realize a \link{DelayedArray} object in memory or on disk.
}

\usage{
realize(x, ...)

\S4method{realize}{ANY}(x, BACKEND=getRealizationBackend())
}

\arguments{
  \item{x}{
    The array-like object to realize.
  }
  \item{...}{
    Additional arguments passed to methods.
  }
  \item{BACKEND}{
    A single string specifying the name of the \emph{realization backend}.
    Use the current realization backend by default i.e. the backend
    returned by \code{\link{getRealizationBackend}()}.
  }
}

\value{
  A \link{DelayedArray} object. More precisely, it returns
  \code{DelayedArray(as.array(x))} when the backend is set to
  \code{NULL} (the default). Otherwise it returns an instance of the
  class associated with the specified backend (which should extend
  \link{DelayedArray}).
}

\seealso{
  \itemize{
    \item \code{\link{getRealizationBackend}} and
          \code{\link{setRealizationBackend}} for getting and setting
          the current \emph{realization backend}.

    \item \link{DelayedArray} objects.

    \item \link{RleArray} objects.

    \item \link[HDF5Array]{HDF5Array} objects in the \pkg{HDF5Array} package.

    \item \link[base]{array} objects in base R.
  }
}

\examples{
library(HDF5Array)
toy_h5 <- system.file("extdata", "toy.h5", package="HDF5Array")
h5ls(toy_h5)
M1 <- HDF5Array(toy_h5, "M1")
M2 <- HDF5Array(toy_h5, "M2")
M3 <- rbind(log(M1), t(M2))

supportedRealizationBackends()
getRealizationBackend()  # backend is set to NULL
realize(M3)  # realization as ordinary array

setRealizationBackend("RleArray")
getRealizationBackend()  # backend is set to "RleArray"
realize(M3)  # realization as RleArray object

setRealizationBackend("HDF5Array")
getRealizationBackend()  # backend is set to "HDF5Array"
realize(M3)  # realization in HDF5 file
}

\keyword{methods}
