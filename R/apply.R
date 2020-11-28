#' @export
futurenow_lapply <- function(
  X, FUN, ..., future.envir = parent.frame(), future.stdout = TRUE,
  future.conditions = NULL, future.globals = TRUE, future.packages = NULL,
  future.lazy = FALSE, future.seed = FALSE, future.scheduling = 1,
  future.chunk.size = NULL, future.label = "future_lapply-%d"
  ){
  options("futurenow.lapply.running" = TRUE)
  options("futurenow.lapply.environment" = future.envir)

  on.exit({
    options("futurenow.lapply.running" = FALSE)
    options("futurenow.lapply.environment" = NULL)
  }, add = TRUE, after = TRUE)

  future.apply::future_lapply(
    X, FUN, ..., future.stdout = future.stdout,
    future.conditions = future.conditions, future.globals = future.globals,
    future.packages = future.packages, future.lazy = future.lazy,
    future.seed = future.seed, future.scheduling = future.scheduling,
    future.chunk.size = future.chunk.size, future.label = future.label)

}
