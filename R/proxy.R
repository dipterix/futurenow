
#' @export
register_name <- function(name, .env = parent.frame()){
  eval_env <- parent.frame()
  name <- substitute(name)
  if(!is.name(name)) {
    stop("register_name only takes name")
  }
  name_str <- as.character(name)
  val <- get0(name_str, envir = eval_env, inherits = TRUE, ifnotfound = NULL)
  .env[[name_str]] <- val
  invisible()
}

#' @export
run_in_master <- function(expr, env = parent.frame(),
                          substitute = TRUE, local_vars = FALSE){
  force(env)
  if(substitute) {
    expr <- substitute(expr)
  }
  gp <- find_globals(expr, env, globals = local_vars)
  mask_env <- new.env(parent = env)
  list2env(gp$globals, mask_env)
  run_env <- new.env(parent = mask_env)
  eval(gp$expr, run_env)
  list2env(as.list(run_env), envir = env)
  invisible()
}

 # must run in master nodes
eval_from_proxy <- function(statusfile, datafile, resultfile, env){
  # need tryCatch to wrap

  tryCatch({
    saveRDS(STATUS_BUSY, statusfile)
    gp <- readRDS(datafile)

    mask_env <- new.env(parent = env)

    # expr and data

    if(length(gp$packages)){
      lapply(gp$packages, requireNamespace, quietly = TRUE)
    }

    if(is.list(gp$globals)){
      list2env(gp$globals, envir = mask_env)
    }

    runtime_env <- new.env(parent = mask_env)
    eval(gp$expr, envir = runtime_env)

    # save runtime_env as a list to resultfile
    saveRDS(as.list(runtime_env), file = resultfile)
  }, error = function(e){
    class(e) <- c(ERROR_EVALUATION, class(e))
    saveRDS(e, file = resultfile)
  }, finally = {
    # save status code
    # fdebug(resultfile)
    saveRDS(STATUS_MASTER_FINISHED, statusfile)
  })
}



inject_proxy <- function(expr, statusfile, datafile, resultfile){
  injected <- bquote({

    options('futurenow.debug' = .(getOption("futurenow.debug", FALSE)))
    options("futurenow.debug.file" = .(getOption("futurenow.debug.file", FALSE)))
    options("futurenow.debug.masteronly" = .(getOption("futurenow.debug.masteronly", FALSE)))
    options("futurenow.master.sessionid" = .(getOption("futurenow.master.sessionid", Sys.getpid())))

    .futurenow <- asNamespace('futurenow')
    run_in_master <- function(expr, env = parent.frame(), substitute = TRUE, local_vars = FALSE){
      .futurenow$fdebug("Sending to master to run")
      force(env)
      if(substitute){
        expr <- substitute(expr)
      }

      if(file.exists(.(resultfile))){
        unlink(.(resultfile))
      }

      # check statusfile, if statusfile is not STATUS_SLAVE_RUNNING,
      # it means other futures are using master node
      tryCatch({
        gp <- .futurenow$find_globals(expr, env, globals = local_vars)

        while(!{status <- readRDS(.(statusfile))} %in% c(.(STATUS_STOP), .(STATUS_SLAVE_RUNNING))){
          .futurenow$fdebug("Waiting for status to clear... ", status)
          Sys.sleep(0.1)
        }
        if(!isTRUE(status == .(STATUS_SLAVE_RUNNING))){
          stop("Future connection is broken")
        }

        # occupy the file
        .futurenow$fdebug("Writing instructions to file...")
        saveRDS(.(STATUS_BUSY), .(statusfile))
        saveRDS(gp, file = .(datafile))

        # let master node know it's ready
        saveRDS(.(STATUS_MASTER_RUNNING), .(statusfile))

      }, error = function(e){
        .futurenow$fdebug("Error: ", e$message)
        class(e) <- c(.(ERROR_SERIALIZATION), e)
        stop(e)
      })
      status <- readRDS(.(statusfile))
      while(!status %in% c(.(STATUS_STOP), .(STATUS_MASTER_FINISHED))) {
        .futurenow$fdebug("Waiting for master to finish the task...", status)
        Sys.sleep(0.2)
        status <- readRDS(.(statusfile))
      }

      if(status == .(STATUS_STOP)){
        # stop!
        .futurenow$fdebug("Broken...")
        stop("Future connection is broken")
      }

      # read results
      if(file.exists(.(resultfile))){
        tryCatch({
          .futurenow$fdebug("Obtaining the results...")
          res <- readRDS(.(resultfile))
          if(inherits(res, 'error')){
            .futurenow$fdebug("Getting Error from master: ", res$message)
            stop(res)
          }
          list2env(res, env)
        }, finally = {
          .futurenow$fdebug("Release resources to others")
          saveRDS(.(STATUS_SLAVE_RUNNING), .(statusfile))
        })
      }

      return()
    }

    res <- tryCatch({

      future.call.arguments <- get0('future.call.arguments', ifnotfound = list())

      do.call(function(...) {
        .(expr)
      }, args = future.call.arguments)

    }, finally = {
      .futurenow$fdebug("Finished.")
      saveRDS(.(STATUS_STOP), .(statusfile))
    })
    res
  })
}
