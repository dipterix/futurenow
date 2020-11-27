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
    packages = unique(c(packages, 'futurenow', fake_gp$packages)),
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
  sp <- switch (
    future$extra$actual_type,
    'MultisessionFuture' = import_future('as_ClusterFuture'),
    'MulticoreFuture' = import_future('as_MulticoreFuture')
  )
  print(class(future))
  future <- sp(future, workers = workers)
  print(class(future))
  future <- structure(future, class = c("FutureNowFuture", class(future)))
  print(class(future))
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

  NextMethod()
}


#' @keywords internal
#' @export
result.FutureNowFuture <- function(future, ...) {
  result <- future$result
  if (!is.null(result)) {
    if (inherits(result, "FutureError")) stop(result)
    return(result)
  }

  if (future$state == "created") {
    future <- run(future)
  }

  # TODO: make sure it's finished?
  NextMethod()
}


await <- function(...) UseMethod("await")

await.ClusterFuture <- local({
  FutureRegistry <- import_future("FutureRegistry")
  requestNode <- import_future("requestNode")

  function(future, ...){
    workers <- future$workers
    reg <- sprintf("workers-%s", attr(workers, "name", exact = TRUE))
    node_idx <- requestNode(await = function() {
      futures <- FutureRegistry(reg, action = "list", earlySignal = FALSE)
      fdebug("Running futures:", length(futures))
      lapply(futures, listener_blocked, max_try = 3L)
      # listener_blocked
      FutureRegistry(reg, action = "collect-first", earlySignal = TRUE)
    }, workers = workers)
    node_idx
  }
})

await.MulticoreFuture <- local({
  FutureRegistry <- import_future("FutureRegistry")
  requestCore <- import_future("requestCore")
  session_uuid <- import_future("session_uuid")

  function(future, ...){
    reg <- sprintf("multicore-%s", session_uuid())
    requestCore(await = function() {
      futures <- FutureRegistry(reg, action = "list", earlySignal = FALSE)
      fdebug("Running futures:", length(futures))
      lapply(futures, listener_blocked, max_try = 3L)
      # listener_blocked
      FutureRegistry(reg, action = "collect-first", earlySignal = TRUE)
    }, workers = future$workers)
  }
})



#' @keywords internal
#' @export
run.FutureNowFuture <- local({
  FutureRegistry <- import_future("FutureRegistry")
  assertOwner <- import_future("assertOwner")
  session_uuid <- import_future("session_uuid")
  requestCore <- import_future("requestCore")
  clusterCall <- import_parallel('clusterCall')
  grmall <- import_future('grmall')
  packages <- import_future('packages')
  hpaste <- import_future('hpaste')
  requirePackages <- import_future('requirePackages')
  globals <- import_future('globals')

  # run.ClusterFuture <- function (future, ...) {
  #   debug <- getOption("future.debug", FALSE)
  #   sendCall <- import_parallel("sendCall")
  #   workers <- future$workers
  #   expr <- getExpression(future)
  #   persistent <- future$persistent
  #   reg <- sprintf("workers-%s", attr(workers, "name", exact = TRUE))
  #   node_idx <- await(future)
  #   future$node <- node_idx
  #   cl <- workers[node_idx]
  #   if (!persistent) {
  #     clusterCall(cl, fun = grmall)
  #   }
  #   packages <- packages(future)
  #   if (future$earlySignal && length(packages) > 0) {
  #     if (debug)
  #       mdebugf("Attaching %d packages (%s) on cluster node #%d ...",
  #               length(packages), hpaste(sQuote(packages)), node_idx)
  #     clusterCall(cl, fun = requirePackages, packages)
  #     if (debug)
  #       mdebugf("Attaching %d packages (%s) on cluster node #%d ... DONE",
  #               length(packages), hpaste(sQuote(packages)), node_idx)
  #   }
  #   globals <- globals(future)
  #   if (length(globals) > 0) {
  #     if (debug) {
  #       total_size <- asIEC(objectSize(globals))
  #       mdebugf("Exporting %d global objects (%s) to cluster node #%d ...",
  #               length(globals), total_size, node_idx)
  #     }
  #     for (name in names(globals)) {
  #       value <- globals[[name]]
  #       if (debug) {
  #         size <- asIEC(objectSize(value))
  #         mdebugf("Exporting %s (%s) to cluster node #%d ...",
  #                 sQuote(name), size, node_idx)
  #       }
  #       suppressWarnings({
  #         clusterCall(cl, fun = gassign, name, value)
  #       })
  #       if (debug)
  #         mdebugf("Exporting %s (%s) to cluster node #%d ... DONE",
  #                 sQuote(name), size, node_idx)
  #       value <- NULL
  #     }
  #     if (debug)
  #       mdebugf("Exporting %d global objects (%s) to cluster node #%d ... DONE",
  #               length(globals), total_size, node_idx)
  #   }
  #   globals <- NULL
  #   FutureRegistry(reg, action = "add", future = future, earlySignal = FALSE)
  #   sendCall(cl[[1L]], fun = geval, args = list(expr))
  #   future$state <- "running"
  #   if (debug)
  #     mdebugf("%s started", class(future)[1])
  #   invisible(future)
  # }





  function(future, ...) {
    if (future$state != "created") {
      label <- future$label
      if (is.null(label)) label <- "<none>"
      msg <- sprintf("A future ('%s') can only be launched once.", label)
      stop(FutureError(msg, future = future))
    }

    ## Assert that the process that created the future is
    ## also the one that evaluates/resolves/queries it.
    assertOwner(future)

    workers <- future$workers
    fdebug("Requesting core...")
    res <- await(future)
    fdebug("Requested: ", deparse(res, nlines = 1))
    saveRDS(STATUS_SLAVE_RUNNING, future$extra$statusfile)

    listener(future = future)
    fdebug("Started listener")

    NextMethod('run')

    invisible(future)
  } ## run()
})
