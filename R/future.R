#' @title Wrapper of 'future'
#' @description Provides additional code for 'future' that allows communication
#' from 'future' clusters back to main session during the runtime
#' @param expr R expression
#' @param envir Environment to evaluate \code{expr}
#' @param listener.delay Intervals for listeners
#' @param substitute,lazy,seed,globals,packages,label,gc See also \code{\link[future]{future}}
#'
#' @examples
#'
#' library(future)
#' library(futurenow)
#'
#' # ---- Example 1: Handle large dataset in main session -------
#' if(interactive()){
#'
#'   # Create a large dataset that will fail the future
#'   x <- rnorm(1e6)
#'   options(future.globals.maxSize = 1000)
#'   plan('multisession', workers = 2L)
#'
#'   # This will fail because x exceed `future.globals.maxSize`
#'   future({
#'     pid <- Sys.getpid()
#'     result <- pid + mean(x)
#'     result
#'   })
#'
#'   fnow <- futurenow({
#'     pid <- Sys.getpid()
#'
#'     run_in_master({
#'       # This code will run in master
#'       mean_x <- mean(x)
#'
#'       # register results back to future
#'       register_name(mean_x)
#'     })
#'
#'     mean_x + pid
#'
#'   })
#'
#'   value(fnow)
#'
#' }
#'
#' # ---- Example 2: Progressbar in Shiny app -------
#' if(interactive()){
#'
#'   library(shiny)
#'
#'   ui <- fluidPage(
#'     actionButton("ok", "Run")
#'   )
#'
#'   server <- function(input, output, session) {
#'     observeEvent(input$ok, {
#'       plan('multisession')
#'
#'       p <- Progress$new(session = session, min = 0, max = 10)
#'
#'       results <- lapply(1:10, function(i){
#'         futurenow({
#'           # Run something
#'           Sys.sleep(1)
#'           # inc progress bar
#'           run_in_master({
#'             p$inc(amount = 1, message = 'Running item', detail = i)
#'           })
#'         })
#'       })
#'       value(results)
#'
#'       p$clone()
#'     })
#'   }
#'
#'   shinyApp(ui, server)
#'
#'
#' }
#'
#'
#' @export
futurenow <- function(expr, envir = parent.frame(), substitute = TRUE, lazy = FALSE,
                      seed = FALSE, globals = TRUE, packages = NULL, label = NULL,
                      gc = FALSE, listener.delay = 0.1, ...) {
  if(substitute){
    expr <- substitute(expr)
  }

  # check whether inject_proxy is needed
  current_plan <- future::plan()
  if(inherits(current_plan, c('sequential', 'transparent'))){
    # no need to inject
    fdebug('Sync plan, regular future')
    return(
      future::future(expr, envir = envir, substitute = FALSE, lazy = lazy,
                     seed = seed, globals = globals, packages = packages,
                     label = label, gc = gc, ...)
    )
  }

  fdebug('async plan')

  # async
  # get globals
  # expr <- quote({as.lazyarray();    a = 1; run_in_master({    b <- a + dipsaus::async({2})    register_name(b)  })})
  fake_expr <- tweakExpression_futurenow(expr)
  gp <- find_globals(fake_expr, env = envir, globals = globals, future.packages = packages)

  while(dir.exists({tmpfile <- tempfile()})){
    fdebug("Temp dir exists, looking for a new one...")
  }
  dir.create(tmpfile, showWarnings = TRUE, recursive = TRUE)
  statusfile <- file.path(tmpfile, 'status')
  datafile <- file.path(tmpfile, 'inputs')
  resultfile <- file.path(tmpfile, 'results')

  fdebug("Inject scripts into future")
  expr <- inject_proxy(expr = expr, statusfile = statusfile,datafile = datafile,resultfile = resultfile)

  fdebug("Start listener")
  saveRDS(STATUS_SLAVE_RUNNING, statusfile)


  fdebug("Go!!!")
  f <- future::future(
    expr, envir = envir, substitute = FALSE, lazy = lazy,
    seed = seed, globals = names(gp$globals), packages = packages,
    label = label, gc = gc, ...)

  if(!is.list(f$extra)){
    f$extra <- list()
  }
  f$extra$statusfile <- statusfile
  f$extra$datafile <- datafile
  f$extra$resultfile <- resultfile
  f$extra$rootdir <- tmpfile
  f$extra$listener_enabled <- TRUE
  f$extra$listener_delay <- listener.delay
  f$extra$env <- envir
  class(f) <- c("futurenow", class(f))

  listener(future = f)

  f
}

#' @export
resolve.futurenow <- function(x, idxs = NULL, recursive = 0, result = FALSE, stdout = FALSE,
                              signal = FALSE, force = FALSE, sleep = 1, value = result,
                              ...) {
  if(x$state == 'created'){
    future::run(x)
  }
  listener_blocked(future = x)
  NextMethod()
}

#' @export
value.futurenow <- function(future, ..., .skip = FALSE){
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

  if(!.skip){
    fdebug("Removing temporary files...")
    unlink(future$extra$rootdir, recursive = TRUE, force = TRUE)
  }

  return(res)
}

# plan(list(tweak(multisession, workers = 2L), tweak(multisession, workers = 2L)))
