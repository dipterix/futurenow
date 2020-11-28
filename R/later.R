has_shiny <- function(){
  if(system.file('', package = 'shiny') != '' &&
     'shiny' %in% loadedNamespaces() &&
     requireNamespace('shiny', quietly = TRUE)){
    return(isTRUE(!is.null(shiny::getDefaultReactiveDomain())))
  }
  return(FALSE)
}

shiny_futurenow_init <- function(session, delay = 0.1){

  if(!is.function(session$userData$...futurenow_timer)){
    timer <- shiny::reactiveTimer(delay * 1000, session = session)
    session$userData$...futurenow_timer <- timer
    shiny::observeEvent(timer(), {
      f <- session$userData$...futurenow_func
      if(is.function(f)){
        try({
          f()
        }, silent = TRUE)
      }
    })
  }


}

evallater <- local({

  last_scheduled <- strptime('19000101010101', "%Y%m%d%H%M%S", tz = 'GMT')

  function(fun, delay){

    # # check whether this is in shiny
    # if(has_shiny()){
    #   # need to run later
    #   session <- shiny::getDefaultReactiveDomain()
    #   if(!is.function(session$userData$...futurenow_timer)){
    #     shiny_futurenow_init(session, getOption("futurenow.shiny.delay", 0.5))
    #   }
    #   session$userData$...futurenow_func <- fun
    # } else {

      now <- Sys.time()
      last_scheduled <<- now
      fdebug(sprintf("Last scheduled: %.2f s, next event: %.2f",
                     as.numeric(now - last_scheduled, unit = 'secs'),
                     later::next_op_secs()))
      later::later(fun, delay = delay)
    # }

  }
})
