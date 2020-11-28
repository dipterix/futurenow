library(future)
library(futurenow)
# futurenow::debug_futurenow()
plan('futurenow', workers=2)

# limit global size to be 1KB
old_limit <- getOption('future.globals.maxSize', Inf)
options(future.globals.maxSize = 1024^2)

a <- 'main session'
b <- rnorm(1e6)


fu <- future({
  a <- 'future session'

  # Case 1: everything in `run_in_master` is in main session
  run_in_master({
    c1 <- sprintf("a is from %s, sum(b)=%.2f is calculated in main session",
                  a, sum(b))
    register_name(c1)
  })

  # Case 2: variable `a` is from local future session
  run_in_master({
    # Run in main session, b will not be serialized
    c2 <- sprintf("a is from %s, sum(b)=%.2f is calculated in main session",
                  a, sum(b))
    register_name(c2)
  }, local_vars = 'a')

  c(c1, c2)
})
value(fu)


# Finalize, clean up
plan('sequential')
options(future.globals.maxSize = old_limit)
