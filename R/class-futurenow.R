#' Create future that can resolve asynchronously in a parallel R session
#' but can talk with the master session
#' @description A multisession or multicore future that uses other R process
#' to evaluate, but allows to run code in the master session during the
#' evaluation.
#' @param expr R expression
#' @param envir Environment the future should be evaluated
#' @param listener.delay Time interval in second the master main session should
#' wait to handle connections from the future instances; default is 0.1
#' @param type The actual type of future to run, choices are
#' `"MultisessionFuture"` and `"MulticoreFuture"`; default is
#' `"MultisessionFuture"`
#' @param workers Max number of parallel instances to run at the same time
#' @param substitute Should `expr` be quoted? Default is `TRUE`
#' @param packages Packages for future instances to load
#' @param env Where to `local_vars` to search variables from
#' @param local_vars Local variable names in the future object to send along
#' to the master session for evaluation; default is `FALSE`, meaning
#' all variables should be in the main session
#' @param name R symbol to register to the future processes
#' @param .env Internally used
#' @param globals,label,... Passed to [future::future()]
#'
#' @return The function `futurenow` and `FutureNowFuture` return
#' [future::future()] instances with class 'FutureNowFuture'. Function
#' `run_in_master` and `register_name` return nothing.
#'
#' @seealso [future::future()], [future::plan()]
#'
#' @details In this package, ``master session'' means the R session which
#' schedules future process. This usually happens in the main process where
#' the users interact with. The ``slave sessions'' or the ``future sessions''
#' are the R processes that asynchronous codes are evaluated.
#'
#' One of the issues with asynchronously evaluating R expressions in another
#' process is data transfer. If the data is an external pointer, this procedure
#' is hard unless using forked process. If the data is too large, transferring
#' the large data around is both time consuming (serialization and needs extra
#' time) and memory consuming. Suppose a user wants to run a data pipeline
#' `A`, `B`, and `C`, where only `B` requires handling the
#' data. One can choose to run `A` asynchronously, then `B` in the
#' main session, then `C` again asynchronously.
#'
#' Normally [future::future()] instance only allows
#' instructions from the master process to the slave nodes. The reversed
#' communication is missing or limited. This prevents the above procedure
#' to run within one future session.
#'
#' Motivated by this objective, `futurenow` is created. In
#' `futurenow`, the above procedure is possible with
#' `run_in_master` and `register_name`.
#'
#' During the asynchronous evaluation, the function `run_in_master` sends
#' the expression inside to the master session to evaluate. Once finished,
#' variables are sent back to the future sessions via `register_name`.
#' The variables sent back via `register_name` can then be used in
#' future sessions as-is.
#'
#' When `run_in_master` asks the master session to evaluate code, the
#' users can also choose which variables in the future sessions along with
#' the instructions; see examples.
#'
#' The other parts are exactly the same as other future objects.
#'
#' @section An Issue with `MulticoreFuture`:
#'
#' The strategy `futurenow` has two internal types:
#' `MultisessionFuture` and `MulticoreFuture`.
#' `MultisessionFuture` spawns a [future::multisession()]
#' process and `MulticoreFuture` spawns a forked
#' [future::multicore()] process. While multisession works in
#' any situation, multicore is faster since it uses a "fork" process that
#' has shared memory and does not need serialization.
#' However, there are some limits using `MulticoreFuture`. For example,
#' it's only supported on 'Mac' and 'Linux' system; if used improperly
#' in 'RStudio', a fork bomb could be malicious to the system (see also
#' <https://en.wikipedia.org/wiki/Fork_bomb>).
#'
#' When choosing `MultisessionFuture` type, a listener will run in the
#' background monitoring requests from the future sessions. However when
#' running with `MulticoreFuture`, the listener could cause a fork bomb.
#' Therefore, the listener will stop running in the background and some
#' future processes may pause at stage `B` (see details, the procedure
#' that requires interaction with the main session) if `run_in_master` is
#' called. In such case, the future instance might never be resolved if the
#' listener is not triggered.
#'
#' To trigger the listener manually, one only needs to "try to collect" the
#' results, for instance, `value(x)`, `resolve(x)`, or
#' `result(x)` will trigger the listener and collect the results.
#' `resolved(x)` will also trigger the listener, but it does not block
#' the main session. When trying to spawn new future instances, the listener
#' will also trigger automatically.
#'
#' @examples
#'
#'
#' if(interactive()){
#'
#'   library(future)
#'   library(futurenow)
#'
#'   plan(futurenow, workers = 2)
#'
#'   # ------------------ Basic example ------------------
#'   plan(futurenow, workers = 2)
#'   f <- future({
#'
#'     # Procedure A
#'     future_pid <- Sys.getpid()
#'
#'     run_in_master({
#'       # Procedure B
#'       master_pid <- Sys.getpid()
#'       register_name(master_pid)
#'     })
#'
#'     # Procedure C
#'     sprintf("Master process PID is %s, future process PID is %s",
#'             master_pid, future_pid)
#'   })
#'
#'   value(f)
#'
#'   # ------------------ Choose variables examples ------------------
#'   plan(futurenow, workers = 2)
#'
#'   a <- 1
#'   f <- future({
#'     a <- 10
#'     run_in_master({
#'       b <- a + 1
#'       register_name(b)
#'     })
#'     b
#'   })
#'   value(f)   # a + 1 (a in master session)
#'
#'   f <- future({
#'     a <- 10
#'     run_in_master({
#'       b <- a + 1
#'       register_name(b)
#'
#'       # local_vars sends variables along with the instruction
#'     }, local_vars = 'a')
#'     b
#'   })
#'   value(f)   # a + 1 (a in future session)
#'
#'   # ------------------ A practical example ------------------
#'   # Create a "large" dataset that will fail the future
#'   x <- rnorm(1e6)
#'   options(future.globals.maxSize = 1024^2)
#'
#'   plan(futurenow, workers = 2)
#'
#'   # This will **fail** because x exceed `future.globals.maxSize`
#'   future({
#'     pid <- Sys.getpid()
#'     result <- pid + mean(x)
#'     result
#'   })
#'
#'   # x is never transferred to future sessions
#'   fnow <- future({
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
#'   value(fnow)
#'
#'   # ------------------ Progressbar in Shiny app ------------------
#'   library(shiny)
#'   plan(futurenow, workers = 2)
#'
#'   ui <- fluidPage(
#'     actionButton("ok", "Run")
#'   )
#'
#'   server <- function(input, output, session) {
#'     observeEvent(input$ok, {
#'       p <- Progress$new(session = session, min = 0, max = 10)
#'
#'       futurenow_lapply(1:10, function(i){
#'         Sys.sleep(0.3)
#'         # inc progress bar
#'         futurenow::run_in_master({
#'           p$inc(amount = 1, message = 'Running item', detail = i)
#'         }, local_vars = 'i')
#'       })
#'
#'       p$close()
#'     })
#'   }
#'
#'   shinyApp(ui, server)
#'
#' }
#'
#' @export
futurenow <- function(expr, envir = parent.frame(), substitute = TRUE,
                      listener.delay = 0.1, globals = TRUE, label = NULL,
                      type = c("MultisessionFuture", "MulticoreFuture"),
                      workers = availableCores(), ...) {
  type <- match.arg(type)

  if(type == "MulticoreFuture"){
    options(future.fork.enable = TRUE)
  }

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

#' @rdname futurenow
#' @export
FutureNowFuture <- function(
  expr = NULL, envir = parent.frame(),
  type = c("MultisessionFuture", "MulticoreFuture"), substitute = TRUE,
  globals = TRUE, packages = NULL, workers = NULL,
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
  expr <- inject_proxy(expr = gp$expr, statusfile = statusfile,
                       datafile = datafile,resultfile = resultfile)

  future <- import_future(type)(
    expr = expr, envir = envir, substitute = FALSE, globals = fake_gp$globals,
    packages = unique(c(packages, 'futurenow', fake_gp$packages, gp$packages)),
    workers = workers, ...)

  if(!is.list(future$extra)){
    future$extra <- list()
  }
  future$extra$statusfile <- statusfile
  future$extra$datafile <- datafile
  future$extra$resultfile <- resultfile
  future$extra$rootdir <- tmpfile
  future$extra$listener_enabled <- TRUE
  future$extra$listener_delay <- listener.delay
  if(getOption("futurenow.lapply.running", FALSE)){
    env1 <- getOption("futurenow.lapply.environment", stop("futurenow_lapply environment not set?"))
    if(!is.environment(env1)){
      stop("futurenow_lapply environment is invalid")
    }
    future$extra$env <- env1
  } else {
    future$extra$env <- envir
  }
  future$extra$actual_type <- type

  future <- as_FutureNowFuture(future, workers = workers)

  future
}


as_FutureNowFuture <- function(future, workers = NULL, ...) {
  future <- structure(future, class = c("FutureNowFuture", class(future)))
  future
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
    # assign('f', futures, envir = globalenv())
    fdebug("Running futures (multicore):", length(futures))
    lapply(futures, listener_blocked, max_try = 3L)
    # listener_blocked
    FutureRegistry(reg, action = "collect-first", earlySignal = TRUE)
  }, workers = future$workers)
}



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
