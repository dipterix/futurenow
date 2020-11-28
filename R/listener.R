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
      if(max_try_left > 0){
        Sys.sleep(delay)
      }
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

check_single <- function(future){
  if(!file.exists(future$extra$statusfile) || !future$extra$listener_enabled) { return(FALSE) }
  reschedule <- tryCatch({
    status_code <- as.character(readRDS(future$extra$statusfile))
    if(length(status_code) != 1){ return(FALSE) }
    switch (
      as.character(status_code),
      '0' = { # STATUS_STOP
        fdebug("Non-blockListener captured FINISH code. (0)")
        future$extra$listener_enabled <- FALSE
        return(FALSE)
      },
      '2' = { # STATUS_MASTER_RUNNING
        fdebug("Non-blockListener captured MASTER code. Evaluating expressions in master node (2)")
        eval_from_proxy(future$extra$statusfile, future$extra$datafile, future$extra$resultfile, future$extra$env)
      }, {
        # STATUS_SLAVE_RUNNING: runtime belongs to slave nodes
        # STATUS_MASTER_FINISHED: slave nodes need to run
        # STATUS_BUSY: writing data in progress
        # other code are unknown. reserved for future use
        #   fdebug(sprintf("Non-blockListener wait... (%s)", status_code))
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

listener <- local({

  queue <- list()
  delay <- 0.1

  function(future){
    fdebug("[Queue] size:", length(queue))
    if(!missing(future)){
      queue[[length(queue) + 1]] <<- future
      delay <<- future$extra$listener_delay

      if(length(queue) >= 2L) {
        return()
      }

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
