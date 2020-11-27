library(future)
library(futurenow)
# plan('futurenow', workers=2, type = 'MulticoreFuture')
plan('futurenow', workers=2)

# limit global size to be 1KB
old_limit <- getOption('future.globals.maxSize', Inf)
options(future.globals.maxSize = 1024)

a <- 'main session'
b <- rnorm(1e6)

# Case 1: everything in `run_in_master` is in main session
fu <- future({
  a <- 'future session'
  run_in_master({
    # Run in main session, b will not be serialized
    c <- list(a = a, m = sum(b))
    register_name(c)
  })
  sprintf("a is from %s, sum(b)=%.2f is calculated in main session",
          c$a, c$m)
})
value(fu)

# Case 2: variable `a` is from local future session
fu <- future({
  a <- 'future session'
  run_in_master({
    # Run in main session, b will not be serialized
    c <- list(a = a, m = sum(b))
    register_name(c)
  }, local_vars = 'a')
  sprintf("a is from %s, sum(b)=%.2f is calculated in main session",
          c$a, c$m)
})
value(fu)


# Finalize, clean up
plan('sequential')
options(future.globals.maxSize = old_limit)
