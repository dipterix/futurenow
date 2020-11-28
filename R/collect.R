
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
