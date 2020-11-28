
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


#' @export
resolve.FutureNowFuture <- function(x, idxs = NULL, recursive = 0, result = FALSE, stdout = FALSE,
                                    signal = FALSE, force = FALSE, sleep = 1, value = result,
                                    ...) {
  fdebug("[resolve.FutureNowFuture] called")
  if(x$state == 'created'){
    future::run(x)
  }
  listener_blocked(future = x)
  NextMethod()
}

#' @export
value.FutureNowFuture <- function(future, ..., .skip = FALSE){
  fdebug("[value.FutureNowFuture] called")
  if(!.skip){
    fdebug("Check future state: ", future$state)
    if(future$state == 'created'){
      future::run(future)
    }
    if(future$state == "running"){
      listener_blocked(future = future)
    }

    fdebug("Getting results")
  }

  res <- NextMethod()

  if(!.skip && dir.exists(future$extra$rootdir)){
    fdebug("Removing temporary files...")
    unlink(future$extra$rootdir, recursive = TRUE, force = TRUE)
  }

  return(res)
}

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

#' @export
getExpression.FutureNowFuture <- function(future, mc.cores = 1L, ...) {
  NextMethod(mc.cores = mc.cores)
}


