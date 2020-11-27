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

    if(!getOption("futurenow.debug.masteronly", FALSE) ||
       getOption("futurenow.master.sessionid", Sys.getpid()) == Sys.getpid()){
      if(is.character(out)){
        cat(sprintf('[%s]', Sys.getpid()), ..., end, file = out, append = TRUE)
      } else {
        cat(sprintf('[%s]', Sys.getpid()), ..., end, file = out)
      }
    }

  }
  invisible()
}

#' @export
debug_futurenow <- function(tmpfile = tempfile(fileext = '.log'), reset = FALSE, master_only = FALSE){

  log <- getOption("futurenow.debug.file", tmpfile)
  if(!is.character(log) || !file.exists(log)){
    log <- tmpfile
  }

  if(reset || !file.exists(log)){
    writeLines('', log)
  }

  try({
    log <- normalizePath(log, mustWork = TRUE)
  }, silent = TRUE)

  options("futurenow.debug.file" = log)
  system(sprintf('open "%s"', log), wait = FALSE)
  options("futurenow.debug" = TRUE)
  options("futurenow.debug.masteronly" = master_only)
  options("futurenow.master.sessionid" = Sys.getpid())
  invisible(log)
}

