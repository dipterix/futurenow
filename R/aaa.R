#' @import future
#' @importFrom globals walkAST

STATUS_STOP = '0'
STATUS_SLAVE_RUNNING  = '1'
STATUS_MASTER_RUNNING = '2'
STATUS_MASTER_FINISHED = '3'
STATUS_BUSY = '4'

ERROR_LISTENER = 'futurenow.master.listener.error'
ERROR_EVALUATION = 'futurenow.master.exec.error'
ERROR_SERIALIZATION = 'futurenow.slave.serialize.error'


fdebug <- function(..., end = '\n', out = getOption('futurenow.debug.file', stdout())){
  if(getOption("futurenow.debug", FALSE)){

    is_master <- getOption("futurenow.master.sessionid", Sys.getpid()) == Sys.getpid()
    if(!getOption("futurenow.debug.masteronly", FALSE) || is_master){
      if(is_master){
        fmt <- sprintf("\x1b[31m[%s][master]", Sys.getpid())
      } else {
        fmt <- sprintf("\x1b[36m  [%s][slave ]", Sys.getpid())
      }
      if(is.character(out)){
        cat(fmt, ..., "\x1b[0m", end, file = out, append = TRUE)
      } else {
        cat(fmt, ..., "\x1b[0m", end, file = out)
      }
    }

  }
  invisible()
}

#' @export
debug_futurenow <- function(tmpfile = stdout(),
                            reset = FALSE, master_only = FALSE){

  log <- tmpfile
  if(!inherits(log, 'connection')){
    if(!file.exists(log) || reset){
      writeLines('', log)
    }
    log <- normalizePath(log)
    system(sprintf('open "%s"', log), wait = FALSE)
  }

  options("futurenow.debug.file" = log)
  options("futurenow.debug" = TRUE)
  options("futurenow.debug.masteronly" = master_only)
  options("futurenow.master.sessionid" = Sys.getpid())
  invisible(log)
}



import_from <- function(name, default = NULL, package) {
  ns <- getNamespace(package)
  if (exists(name, mode = "function", envir = ns, inherits = FALSE)) {
    get(name, mode = "function", envir = ns, inherits = FALSE)
  } else if (!is.null(default)) {
    default
  } else {
    stop(sprintf("No such '%s' function: %s()", package, name))
  }
}

import_future <- function(name, default = NULL) {
  import_from(name, default = default, package = "future")
}

import_parallel <- function(name, default = NULL) {
  import_from(name, default = default, package = "parallel")
}

stop_if_not <- function (...) {
  res <- list(...)
  for (ii in 1L:length(res)) {
    res_ii <- .subset2(res, ii)
    if (length(res_ii) != 1L || is.na(res_ii) || !res_ii) {
      mc <- match.call()
      call <- deparse(mc[[ii + 1]], width.cutoff = 60L)
      if (length(call) > 1L)
        call <- paste(call[1L], "....")
      stop(sprintf("%s is not TRUE", sQuote(call)), call. = FALSE,
           domain = NA)
    }
  }
  NULL
}
