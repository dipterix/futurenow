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
      session$userData$...futurenow_func <- NULL
      if(is.function(f)){
        f()
      }
    })
  }


}

evallater <- function(fun, delay){

  # check whether this is in shiny
  if(has_shiny()){
    # need to run later
    session <- shiny::getDefaultReactiveDomain()
    if(!is.function(session$userData$...futurenow_timer)){
      shiny_futurenow_init(session, delay)
    }
    session$userData$...futurenow_func <- fun
  } else {
    later::later(fun, delay = delay)
  }

}
