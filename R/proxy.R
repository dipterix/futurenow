
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
run_in_master <- function(expr, env = parent.frame(), substitute = TRUE){
  force(env)
  if(substitute) {
    expr <- substitute(expr)
  }
  run_env <- new.env(parent = env)
  eval(expr, run_env)
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
    fdebug(resultfile)
    saveRDS(STATUS_MASTER_FINISHED, statusfile)
  })
}

listener_blocked <- function(future, max_try = Inf){

  fdebug("Listener-blocking")

  statusfile <- future$extra$statusfile
  datafile <- future$extra$datafile
  resultfile <- future$extra$resultfile
  delay <- future$extra$listener_delay
  env <- future$extra$env

  # disable non-blocked listener
  if(!file.exists(statusfile)) { return() }

  force_stop <- FALSE
  max_try_left <- max_try

  tryCatch({
    while(!force_stop && max_try_left > 0){
      status_code <- as.character(readRDS(statusfile))
      if(length(status_code) != 1){ return() }


      switch (
        as.character(status_code),
        '0' = { # STATUS_STOP
          fdebug("BlockListener captured FINISH code. (0)")
          future$extra$listener_enabled <- FALSE
          force_stop <- TRUE
        },
        '2' = { # STATUS_MASTER_RUNNING
          fdebug("BlockListener captured MASTER code. Evaluating expressions in master node (2)")
          eval_from_proxy(statusfile, datafile, resultfile, env)
        }, {
          if(status_code != '1'){
            fdebug(sprintf("BlockListener wait... (%s)", status_code))
          }
        }
      )
      max_try_left = max_try_left - 1
      Sys.sleep(delay)
    }

  }, error = function(e){
    fdebug("Error: ", e$messsage)
    class(e) <- c(ERROR_LISTENER, class(e))
    saveRDS(e, file = resultfile)
    saveRDS(STATUS_STOP, statusfile)
    force_stop <<- TRUE
  })

  return(force_stop)

}

check_single <- local({
  last_flag <- '-1'
  function(future){
    if(!file.exists(future$extra$statusfile) || !future$extra$listener_enabled) { return(FALSE) }
    reschedule <- tryCatch({
      status_code <- as.character(readRDS(future$extra$statusfile))
      if(length(status_code) != 1){ return(FALSE) }
      switch (
        as.character(status_code),
        '0' = { # STATUS_STOP
          # if(!isTRUE(last_flag == status_code)){
          #   fdebug("Non-blockListener captured FINISH code. (0)")
          #   last_flag <<- status_code
          # }
          future$extra$listener_enabled <- FALSE
          return(FALSE)
        },
        '2' = { # STATUS_MASTER_RUNNING
          # if(!isTRUE(last_flag == status_code)){
          #   fdebug("Non-blockListener captured MASTER code. Evaluating expressions in master node (2)")
          #   last_flag <<- status_code
          # }

          eval_from_proxy(future$extra$statusfile, future$extra$datafile, future$extra$resultfile, future$extra$env)
        }, {
          # STATUS_SLAVE_RUNNING: runtime belongs to slave nodes
          # STATUS_MASTER_FINISHED: slave nodes need to run
          # STATUS_BUSY: writing data in progress
          # other code are unknown. reserved for future use
          # if(!isTRUE(last_flag == status_code)){
          #   fdebug(sprintf("Non-blockListener wait... (%s)", status_code))
          #   last_flag <<- status_code
          # }
        }
      )

      TRUE

    }, error = function(e){
      fdebug("Error: ", e$message)
      class(e) <- c(ERROR_LISTENER, class(e))
      saveRDS(e, file = future$extra$resultfile)
      saveRDS(STATUS_MASTER_FINISHED, future$extra$statusfile)
      FALSE
    })

  }
})

listener <- local({

  queue <- list()
  delay <- 0.1

  function(future){
    if(!missing(future)){
      queue[[length(queue) + 1]] <<- future
      delay <<- future$extra$listener_delay
    }

    if(!length(queue)){ return() }

    fdebug("Checking master tasks")
    reschedule <- sapply(queue, check_single)


    if(length(reschedule)){
      fdebug("Total active cases: (", sum(reschedule), "), finished tasks (", sum(!reschedule), ")", sep = '')
      if(any(!reschedule)) {
        queue <<- queue[reschedule]
      }

      if(any(reschedule)) {
        # Re-schedule
        fdebug("Reschedule checks...")
        evallater(function(){ listener() }, delay = delay)
        return()
      }
    }
    fdebug("All tasks finished.")
  }


})



inject_proxy <- function(expr, statusfile, datafile, resultfile){
  rlang::quo_squash(rlang::quo({

    options('futurenow.debug' = !!getOption("futurenow.debug", FALSE))
    options("futurenow.debug.file" = !!getOption("futurenow.debug.file", FALSE))
    options("futurenow.debug.masteronly" = !!getOption("futurenow.debug.masteronly", FALSE))
    options("futurenow.master.sessionid" = !!getOption("futurenow.master.sessionid", Sys.getpid()))

    .futurenow <- asNamespace('futurenow')

    run_in_master <- function(expr, env = parent.frame(), substitute = TRUE){
      .futurenow$fdebug("Sending to master to run")
      force(env)
      if(substitute){
        expr <- substitute(expr)
      }

      if(file.exists(!!resultfile)){
        unlink(!!resultfile)
      }

      # check statusfile, if statusfile is not STATUS_SLAVE_RUNNING,
      # it means other futures are using master node
      tryCatch({
        gp <- .futurenow$find_globals(expr, env)

        while(!{status <- readRDS(!!statusfile)} %in% c(!!STATUS_STOP, !!STATUS_SLAVE_RUNNING)){
          .futurenow$fdebug("Waiting for status to clear... ", status)
          Sys.sleep(0.1)
        }
        if(!isTRUE(status == !!STATUS_SLAVE_RUNNING)){
          stop("Future connection is broken")
        }

        # occupy the file
        .futurenow$fdebug("Writing instructions to file...")
        saveRDS(!!STATUS_BUSY, !!statusfile)
        saveRDS(gp, file = !!datafile)

        # let master node know it's ready
        saveRDS(!!STATUS_MASTER_RUNNING, !!statusfile)

      }, error = function(e){
        .futurenow$fdebug("Error: ", e$message)
        class(e) <- c(!!ERROR_SERIALIZATION, e)
        stop(e)
      })
      status <- readRDS(!!statusfile)
      while(!status %in% c(!!STATUS_STOP, !!STATUS_MASTER_FINISHED)) {
        .futurenow$fdebug("Waiting for master to finish the task...", status)
        Sys.sleep(0.2)
        status <- readRDS(!!statusfile)
      }

      if(status == !!STATUS_STOP){
        # stop!
        .futurenow$fdebug("Broken...")
        stop("Future connection is broken")
      }

      # read results
      if(file.exists(!!resultfile)){
        tryCatch({
          .futurenow$fdebug("Obtaining the results...")
          res <- readRDS(!!resultfile)
          if(inherits(res, 'error')){
            .futurenow$fdebug("Getting Error from master: ", res$message)
            stop(res)
          }
          list2env(res, env)
        }, finally = {
          .futurenow$fdebug("Release resources to others")
          saveRDS(!!STATUS_SLAVE_RUNNING, !!statusfile)
        })
      }

      return()
    }
    res <- tryCatch({
      !!expr
    }, finally = {
      .futurenow$fdebug("Finished.")
      saveRDS(!!STATUS_STOP, !!statusfile)
    })
    return(res)
  }))
}
