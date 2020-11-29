#' A wrapper of [future.apply::future_lapply()] that has the correct
#' environment
#' @description Fixes [future.apply::future_lapply()] issue where
#' the environment is not set properly.
#' @param X Vector or list, R objects
#' @param FUN Function to apply on each element of `X`
#' @param ... Further argument to be passed to `FUN` or
#' [future.apply::future_eapply()]
#' @param future.envir Where the future instances should be created
#' @param future.globals A logical, a character vector, or a named list for
#' controlling how global variables are handled; See
#' [future.apply::future_eapply()]
#' @param future.packages Character vector of packages for future instances to
#' load
#' @param future.lazy Whether to start evaluation immediately
#' @param future.seed A logical or an integer (of length one or seven), or a
#' list of `length(X)` with prespecified random seeds; see
#' [future.apply::future_eapply()]
#' @param future.scheduling,future.chunk.size See
#' [future.apply::future_eapply()]
#' @param future.label Label to be assigned to each future instances
#'
#' @return A list with same length and names as `X`. See
#' [base::lapply()] for details.
#'
#' @seealso [future.apply::future_eapply()],[base::lapply()]
#' @export
futurenow_lapply <- function(
  X, FUN, ..., future.envir = parent.frame(),
  future.globals = TRUE, future.packages = NULL,
  future.lazy = FALSE, future.seed = FALSE, future.scheduling = 1,
  future.chunk.size = NULL, future.label = "futurenow_lapply-%d"
  ){
  options("futurenow.lapply.running" = TRUE)
  options("futurenow.lapply.environment" = future.envir)

  on.exit({
    options("futurenow.lapply.running" = FALSE)
    options("futurenow.lapply.environment" = NULL)
  }, add = TRUE, after = TRUE)

  future.apply::future_lapply(
    X, FUN, ...,
    future.globals = future.globals,
    future.packages = future.packages, future.lazy = future.lazy,
    future.seed = future.seed, future.scheduling = future.scheduling,
    future.chunk.size = future.chunk.size, future.label = future.label)

}
