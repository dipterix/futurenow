
# futurenow

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://www.tidyverse.org/lifecycle/#experimental)
[![R build status](https://github.com/dipterix/futurenow/workflows/R-CMD-check/badge.svg)](https://github.com/dipterix/futurenow/actions)
[![Travis build status](https://travis-ci.org/dipterix/futurenow.svg?branch=main)](https://travis-ci.org/dipterix/futurenow)
[![CRAN status](https://www.r-pkg.org/badges/version/futurenow)](https://CRAN.R-project.org/package=futurenow)
<!-- badges: end -->

## Installation

This repository is currently not on CRAN.

``` r
# install.packages("remotes")
remotes::install_github("dipterix/futurenow")
```


## Introduction

The R package [**future**](https://github.com/HenrikBengtsson/future) provides a unified framework for parallel and distributed processing in R using `future`s. A `future` is usually a separated process that runs R command without blocking its master session, which is often the R session users are operating on.

One of the issues with asynchronously evaluating R expressions in another process is data transfer. If the data is an external pointer, this procedure is hard unless using forked process. If the data is too large, transferring the large data around is both time consuming (serialization and needs extra time) and memory consuming. Then the user might want to run the following data pipeline:

![Diagram: `futurenow` runs pipeline B in the main session](https://github.com/dipterix/futurenow/raw/main/inst/diagram.png)

Process A runs asynchronously, which might take a while. Process B requires the results from A and has to run in the main session. The results of B is sent back to the future session to continue C. Only process B blocks the main session.

## Example

This is a basic example which shows you how to solve a common problem:

``` r
library(future)
library(futurenow)

# This is the first step 
plan(futurenow, workers = 2)

# Generate a "large data"
x <- seq_len(1e8)

a <- 1

f <- future({

  # pipeline A ...
  a <- 10
  
  # pipeline B, send to master session
  run_in_master({
    b <- a + min(x)
    
    # Register `b` to the future session
    register_name(b)

    # local_vars sends variables along with the instruction
  }, local_vars = 'a')
  
  # pipeline C
  sprintf("a + min(x) = %.1f", b)
  
})

value(f)
#> [1] "a + min(x) = 11.0"
```

`run_in_master` sends expression back to the main session. The returned value should be wrapped by `register_name`.

`local_vars` indicates which variables are to be sent to the main session. Default is none, then all the variables should be in the main session. For example:


``` r
a <- 1

f <- future({
  a <- 10
  run_in_master({
    b <- a
    register_name(b)
  }, local_vars = FALSE)
  sprintf("a = %.1f", b)
})

value(f)
#> [1] "a = 1.0"
```

Two `a` are defined: in the main session `a=1` while in the future `a=10`. `local_vars=FALSE` means pipeline B only uses `a` in the main session.


## `futurenow_lapply`, and A Shiny Progress Example

The function `futurenow_lapply` asynchronously applies a function to each elements of input vectors and returns a list. Updating shiny progress bar in a parallel process can be achieved via `run_in_master`.

``` r
library(future)
library(futurenow)
library(shiny)
plan(futurenow, workers = 2)

ui <- fluidPage(
  actionButton("ok", "Run")
)

server <- function(input, output, session) {
  observeEvent(input$ok, {
    p <- Progress$new(session = session, min = 0, max = 10)

    futurenow_lapply(1:10, function(i){
      Sys.sleep(0.3)
      # inc progress bar
      run_in_master({
        p$inc(amount = 1, message = 'Running item', detail = i)
      }, local_vars = 'i')
    })

    p$close()
  })
}

shinyApp(ui, server)

```


## An Issue with `MulticoreFuture`


The strategy `futurenow` is currently supporting two internal types: `MultisessionFuture` and `MulticoreFuture`. `MultisessionFuture` spawns a `multisession` process and `MulticoreFuture` spawns a forked `multicore` process. While `multisession` works in any situation, `multicore` is faster since it uses a "fork" process that has shared memory and does not need serialization. However, there are some limits using `MulticoreFuture`. For example, it's only supported on `Mac` and Linux` system; if used improperly, a [fork bomb](https://en.wikipedia.org/wiki/Fork_bomb) could be malicious to the system.

When choosing `MultisessionFuture` type, a listener will run in the background monitoring requests from the future sessions. However when running with `MulticoreFuture`, the listener could cause a fork bomb. Therefore, the listener will stop running in the background and some future processes may pause at pipeline B (see figure above, the procedure that requires interaction with the main session) if `run_in_master` is called. In such case, the future instance might never be resolved if the listener is not triggered. Users need to trigger the listeners manually.

To trigger the listener manually, one only needs to "try to collect" the results, for instance, `value(x)`, `resolve(x)`, or `result(x)` will trigger the listener to collect the results. `resolved(x)` will also trigger the listener, but it does not block the main session. When trying to spawn new future instances, the listener will also trigger automatically.

``` r
library(future)
library(futurenow)
plan(futurenow, type = 'MulticoreFuture', workers = 2)

func <- function(){
  now = Sys.time()
  future({
    Sys.sleep(1)
    msg = sprintf("Procedure A finished: %.1f s", Sys.time() - now)
    run_in_master({
      msg = c(msg, sprintf("Procedure B finished: %.1f s", Sys.time() - now))
      register_name(msg)
    }, local_vars = 'msg')
    Sys.sleep(2)
    msg = c(msg, sprintf("Procedure C finished: %.1f s", Sys.time() - now))
    paste(msg, collapse = '\n')
  })
}

# The listener still runs if single future is spawned 

f <- func()

# wait for at least 1 seconds
cat(value(f))   
#> Procedure A finished: 1.0 s
#> Procedure B finished: 1.1 s   <--- B is executed right after A
#> Procedure C finished: 3.2 s

# Creating two future instances and listener is stopped

f1 <- func(); f2 <- func(); f3 <- func(); 
futurenow:::listener()

# IMPORTANT, wait for at least 1 seconds
cat(value(f3))
# > Procedure A finished: 1.0 s
# > Procedure B finished: 9.2 s  <--- I waited for 8 seconds to collect value
# > Procedure C finished: 11.4 s
```


