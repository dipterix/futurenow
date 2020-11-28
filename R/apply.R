#' A wrapper of \code{\link[future.apply]{future_lapply}} that has the correct
#' environment
#' @description Fixes \code{\link[future.apply]{future_lapply}} issue where
#' the environment is not set properly.
#' @param X Vector or list, R objects
#' @param FUN Function to apply on each element of \code{X}
#' @param ... Further argument to be passed to \code{FUN} or
#' \code{\link[future.apply]{future_eapply}}
#' @param future.envir Where the future instances should be created
#' @param future.globals A logical, a character vector, or a named list for
#' controlling how global variables are handled; See
#' \code{\link[future.apply]{future_eapply}}
#' @param future.packages Character vector of packages for future instances to
#' load
#' @param future.lazy Whether to start evaluation immediately
#' @param future.seed A logical or an integer (of length one or seven), or a
#' list of \code{length(X)} with pre-generated random seeds; see
#' \code{\link[future.apply]{future_eapply}}
#' @param future.scheduling,future.chunk.size See
#' \code{\link[future.apply]{future_eapply}}
#' @param future.label Label to be assigned to each future instances
#'
#' @return A list with same length and names as \code{X}. See
#' \code{\link[base]{lapply}} for details.
#'
#' @seealso \code{\link[future.apply]{future_eapply}},\code{\link[base]{lapply}}
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
