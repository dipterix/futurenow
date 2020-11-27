require(futurenow)
future::plan('multisession', workers=2)

e <- new.env()
a <- 1
b <- 2
fu <- futurenow({
  a <- 2
  Sys.sleep(3)
  run_in_master({
    c <- a + b
    register_name(c)
  })
  c + 2
}, envir = e)

# future::value(f)
dir.exists(fu$extra$rootdir)
future::resolve(fu)
future::value(fu)
dir.exists(fu$extra$rootdir)

future::plan('sequential')
