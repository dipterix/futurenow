#' @export
futurenow <- function(expr, envir = parent.frame(), substitute = TRUE,
                      listener.delay = 0.1, globals = TRUE, label = NULL,
                      type = c("MultisessionFuture", "MulticoreFuture"),
                      workers = availableCores(), ...) {
  type = match.arg(type)
  if (substitute) expr <- substitute(expr)

  if (is.null(workers)) workers <- availableCores()

  future <- FutureNowFuture(expr = expr, envir = envir, substitute = FALSE,
                        globals = globals, label = label, workers = workers,
                        listener.delay = listener.delay, type = type,
                        ...)

  if (!future$lazy) future <- run(future)

  future
}
class(futurenow) <- c("futurenow", "multiprocess", "future", "function")

#' @export
FutureNowFuture <- function(
  expr = NULL, envir = parent.frame(),
  type = c("MultisessionFuture", "MulticoreFuture"), substitute = TRUE,
  globals = TRUE, packages = NULL, label = NULL, workers = NULL,
  listener.delay = 0.1, ...) {
  type <- match.arg(type)
  if (substitute) expr <- substitute(expr)
  ## Record globals

  fake_expr <- tweakExpression_futurenow(expr)
  fake_gp <- getGlobalsAndPackages(fake_expr, envir = envir, globals = globals)
  gp <- getGlobalsAndPackages(expr, envir = envir, globals = FALSE)

  while(dir.exists({tmpfile <- tempfile()})){
    fdebug("Temp dir exists, looking for a new one...")
  }
  dir.create(tmpfile, showWarnings = TRUE, recursive = TRUE)
  statusfile <- file.path(tmpfile, 'status')
  datafile <- file.path(tmpfile, 'inputs')
  resultfile <- file.path(tmpfile, 'results')

  fdebug("Inject scripts into future")
  expr <- inject_proxy(expr = gp$expr, statusfile = statusfile,datafile = datafile,resultfile = resultfile)

  future <- import_future(type)(
    expr = expr, envir = envir, substitute = FALSE, globals = fake_gp$globals,
    packages = unique(c(packages, 'futurenow', fake_gp$packages, gp$packages)),
    label = label, workers = workers, ...)

  if(!is.list(future$extra)){
    future$extra <- list()
  }
  future$extra$statusfile <- statusfile
  future$extra$datafile <- datafile
  future$extra$resultfile <- resultfile
  future$extra$rootdir <- tmpfile
  future$extra$listener_enabled <- TRUE
  future$extra$listener_delay <- listener.delay
  future$extra$env <- envir
  future$extra$actual_type <- type

  future <- as_FutureNowFuture(future, workers = workers)

  future
}


as_FutureNowFuture <- function(future, workers = NULL, ...) {
  future <- structure(future, class = c("FutureNowFuture", class(future)))
  future
}



#' @export
getExpression.FutureNowFuture <- function(future, mc.cores = 1L, ...) {
  NextMethod(mc.cores = mc.cores)
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Future API
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#' @keywords internal
#' @export
resolved.FutureNowFuture <- function(x, ...) {
  # check status file
  if(!isTRUE(file.exists(x$extra$statusfile))){
    return(TRUE)
  }

  is_stopped <- tryCatch({
    isTRUE(readRDS(x$extra$statusfile) == STATUS_STOP)
  }, error = function(e){
    TRUE
  })

  if(is_stopped){
    return(TRUE)
  }

  # Still running, but let's block it for a second to see if there's any
  # tasks blocking the session
  listener_blocked(x, max_try = 1L)

  NextMethod()
}


#' @keywords internal
#' @export
result.FutureNowFuture <- function(future, ...) {
  fdebug("[result.FutureNowFuture] called")
  result <- future$result
  if (!is.null(result)) {
    if (inherits(result, "FutureError")) stop(result)
    return(result)
  }
  fdebug("Check future state: ", future$state)
  if (future$state == "created") {
    future <- run(future)
  }

  if(future$state == "running"){
    listener_blocked(future = future)
  }

  fdebug("Getting results")

  res <- NextMethod()

  fdebug("Removing temporary files...")
  if(dir.exists(future$extra$rootdir)){
    unlink(future$extra$rootdir, recursive = TRUE, force = TRUE)
  }

  res
}


await <- function(...) UseMethod("await")

await.MultisessionFuture <- function(future, ...){
  FutureRegistry <- import_future("FutureRegistry")
  requestNode <- import_future("requestNode")

  fdebug("Requesting node...")
  workers <- future$workers
  reg <- sprintf("workers-%s", attr(workers, "name", exact = TRUE))
  # future:::FutureRegistry(reg, 'list')
  node_idx <- requestNode(await = function() {
    futures <- FutureRegistry(reg, action = "list", earlySignal = FALSE)
    fdebug("Running futures (multisession):", length(futures))
    lapply(futures, listener_blocked, max_try = 3L)
    # listener_blocked
    FutureRegistry(reg, action = "collect-first", earlySignal = TRUE)
  }, workers = workers)
  node_idx
}

await.MulticoreFuture <- function(future, ...){

  FutureRegistry <- import_future("FutureRegistry")
  requestCore <- import_future("requestCore")
  session_uuid <- import_future("session_uuid")

  reg <- sprintf("multicore-%s", session_uuid())
  fdebug("Requesting core...")
  requestCore(await = function() {
    futures <- FutureRegistry(reg, action = "list", earlySignal = FALSE)
    fdebug("Running futures (multicore):", length(futures))
    lapply(futures, listener_blocked, max_try = 3L)
    # listener_blocked
    FutureRegistry(reg, action = "collect-first", earlySignal = TRUE)
  }, workers = future$workers)
}



#' @keywords internal
#' @export
run.FutureNowFuture <- function(future, ...) {
  assertOwner <- import_future("assertOwner")

  if (future$state != "created") {
    label <- future$label
    if (is.null(label)) label <- "<none>"
    msg <- sprintf("A future ('%s') can only be launched once.", label)
    stop(FutureError(msg, future = future))
  }

  ## Assert that the process that created the future is
  ## also the one that evaluates/resolves/queries it.
  assertOwner(future)


  res <- await(future)
  fdebug("Requested: ", deparse(res, nlines = 1))
  saveRDS(STATUS_SLAVE_RUNNING, future$extra$statusfile)

  NextMethod('run')

  listener(future = future)
  fdebug("Started listener")

  invisible(future)
}
