### =========================================================================
### Block processing utilities
### -------------------------------------------------------------------------
###


### NOT exported but used in the HDF5Array package!
get_verbose_block_processing <- function()
{
    getOption("DelayedArray.verbose.block.processing", default=FALSE)
}

### NOT exported but used in the HDF5Array package!
set_verbose_block_processing <- function(verbose)
{
    if (!isTRUEorFALSE(verbose))
        stop("'verbose' must be TRUE or FALSE")
    old_verbose <- get_verbose_block_processing()
    options(DelayedArray.verbose.block.processing=verbose)
    old_verbose
}


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### set/getAutoBPPARAM()
###

### By default (i.e. when no argument is specified), no BiocParallel backend
### is set and evaluation is sequential.
### Beware that SnowParam() on Windows is quite inefficient for block
### processing (it introduces **a lot** of overhead) so it's better to stick
### to sequential evaluation on this platform.
### See https://github.com/Bioconductor/BiocParallel/issues/78
setAutoBPPARAM <- function(BPPARAM=NULL)
{
    if (!is.null(BPPARAM)) {
        if (!requireNamespace("BiocParallel", quietly=TRUE))
            stop(wmsg("Couldn't load the BiocParallel package. Please ",
                      "install the BiocParallel package and try again."))
        if (!is(BPPARAM, "BiocParallelParam"))
            stop(wmsg("'BPPARAM' must be a BiocParallelParam ",
                      "object from the BiocParallel package"))
    }
    set_user_option("auto.BPPARAM", BPPARAM)
}

getAutoBPPARAM <- function() get_user_option("auto.BPPARAM")


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Walking on the blocks
###
### 2 utility functions to process array-like objects by block.
###

### 'x' must be an array-like object.
### 'FUN' is the callback function to be applied to each block of array-like
### object 'x'. It must take at least 1 argument which is the current array
### block as an ordinary array or matrix.
### 'grid' must be an ArrayGrid object describing the block partitioning
### of 'x'. If not supplied, the grid returned by 'defaultAutoGrid(x)' is
### used. The effective grid (i.e. 'grid' or 'defaultAutoGrid(x)'), current
### block number, and current viewport (i.e. the ArrayViewport object
### describing the position of the current block w.r.t. the effective grid),
### can be obtained from within 'FUN' with 'effectiveGrid(block)',
### 'currentBlockId(block)', and 'currentViewport(block)', respectively.
### 'BPPARAM' is passed to bplapply(). In theory, the best performance should
### be obtained when bplapply() uses a post office queue model. According to
### https://support.bioconductor.org/p/96856/#96888, this can be achieved by
### setting the nb of tasks to the nb of blocks (i.e. with
### BPPARAM=MulticoreParam(tasks=length(grid))). However, in practice, that
### seems to be slower than using tasks=0 (the default). Investigate this!
blockApply <- function(x, FUN, ..., grid=NULL, as.sparse=FALSE,
                                    BPPARAM=getAutoBPPARAM())
{
    FUN <- match.fun(FUN)
    grid <- normarg_grid(grid, x)
    nblock <- length(grid)
    bplapply2(seq_len(nblock),
        ## TODO: Not a pure function (because it refers to 'nblock', 'grid',
        ## and 'x') so will probably fail with parallelization backends that
        ## don't use a fork (e.g. SnowParam on Windows). Test and confirm this.
        ## FIXME: The fix is to add arguments to the function so that the
        ## objects can be passed to it.
        function(bid) {
            if (get_verbose_block_processing()) {
                message("Processing block ", bid, "/", nblock, " ... ",
                        appendLF=FALSE)
                on.exit(message("OK"))
            }
            viewport <- grid[[bid]]
            block <- read_block(x, viewport, as.sparse=as.sparse)
            attr(block, "from_grid") <- grid
            attr(block, "block_id") <- bid
            FUN(block, ...)
        },
        BPPARAM=BPPARAM
    )
}

### A Reduce-like function. Not parallelized yet.
blockReduce <- function(FUN, x, init, BREAKIF=NULL, grid=NULL, as.sparse=FALSE)
{
    FUN <- match.fun(FUN)
    if (!is.null(BREAKIF))
        BREAKIF <- match.fun(BREAKIF)
    grid <- normarg_grid(grid, x)
    nblock <- length(grid)
    for (bid in seq_len(nblock)) {
        if (get_verbose_block_processing())
            message("Processing block ", bid, "/", nblock, " ... ",
                    appendLF=FALSE)
        viewport <- grid[[bid]]
        block <- read_block(x, viewport, as.sparse=as.sparse)
        attr(block, "from_grid") <- grid
        attr(block, "block_id") <- bid
        init <- FUN(block, init)
        if (get_verbose_block_processing())
            message("OK")
        if (!is.null(BREAKIF) && BREAKIF(init)) {
            if (get_verbose_block_processing())
                message("BREAK condition encountered")
            break
        }
    }
    init
}

effectiveGrid <- function(block)
{
    if (!is.array(block))
        stop("'block' must be an ordinary array")
    if (!("from_grid" %in% names(attributes(block))))
        stop(wmsg("'block' has no \"from_grid\" attribute. ",
                  "Was effectiveGrid() called in a blockApply() loop?"))
    attr(block, "from_grid", exact=TRUE)
}

currentBlockId <- function(block)
{
    if (!is.array(block))
        stop("'block' must be an ordinary array")
    if (!("block_id" %in% names(attributes(block))))
        stop(wmsg("'block' has no \"block_id\" attribute. ",
                  "Was currentBlockId() called in a blockApply() loop?"))
    attr(block, "block_id", exact=TRUE)
}

currentViewport <- function(block)
    effectiveGrid(block)[[currentBlockId(block)]]


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### OLD - Walking on the blocks
### OLD -
### OLD - 3 utility functions to process array-like objects by block.
### OLD -
### OLD - Still used by the DelayedMatrixStats package.

### An lapply-like function.
block_APPLY <- function(x, APPLY, ..., sink=NULL, block_maxlen=NULL)
{
    APPLY <- match.fun(APPLY)
    x_dim <- dim(x)
    if (any(x_dim == 0L)) {
        chunk_grid <- NULL
    } else {
        ## Using chunks of length 1 (i.e. max resolution chunk grid) is just
        ## a trick to make sure that defaultAutoGrid() returns linear blocks.
        chunk_grid <- RegularArrayGrid(x_dim, rep.int(1L, length(x_dim)))
    }
    grid <- defaultAutoGrid(x, block_maxlen, chunk_grid,
                               block.shape="first-dim-grows-first")
    nblock <- length(grid)
    lapply(seq_len(nblock),
        function(bid) {
            if (get_verbose_block_processing())
                message("Processing block ", bid, "/", nblock, " ... ",
                        appendLF=FALSE)
            viewport <- grid[[bid]]
            block <- read_block(x, viewport)
            block_ans <- APPLY(block, ...)
            if (!is.null(sink)) {
                write_block(sink, viewport, block_ans)
                block_ans <- NULL
            }
            if (get_verbose_block_processing())
                message("OK")
            block_ans
        })
}

### A convenience wrapper around block_APPLY() to process a matrix-like
### object by block of columns.
colblock_APPLY <- function(x, APPLY, ..., sink=NULL)
{
    x_dim <- dim(x)
    if (length(x_dim) != 2L)
        stop("'x' must be a matrix-like object")
    APPLY <- match.fun(APPLY)
    ## We're going to walk along the columns so need to increase the block
    ## length so each block is made of at least one column.
    block_maxlen <- max(getAutoBlockLength(type(x)), x_dim[[1L]])
    block_APPLY(x, APPLY, ..., sink=sink, block_maxlen=block_maxlen)
}

