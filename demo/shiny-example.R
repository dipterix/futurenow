library(future)
library(futurenow)
library(shiny)
# debug_futurenow(tmpfile = stdout(), reset = TRUE, master_only = TRUE)
ui <- fluidPage(
  actionButton("ok", "Run")
)

session <- shiny::MockShinySession$new()

server <- function(input, output, session) {

  observeEvent(input$ok, {
    p <- Progress$new(session = session, min = 0, max = 10)
    plan(futurenow)

    on.exit({
      p$close()
      # plan(sequential)
    }, add = TRUE)


    futurenow::debug_futurenow('.debug.log', reset = TRUE, master_only = TRUE)

    # future.apply::future_lapply(1:10, function(i){
    #   # Run something
    #   Sys.sleep(1)
    #   # inc progress bar
    #   run_in_master({
    #     p$inc(amount = 1, message = 'Running item',
    #           detail = sprintf('Processing %d', i))
    #   }, local_vars = 'i')
    # })
    results <- lapply(1:3, function(i){
      future({
        # Run something
        Sys.sleep(1)
        # inc progress bar
        run_in_master({
          p$inc(amount = 1, message = 'Running item',
                detail = sprintf('Processing %d', i))
        })
      }) -> f
      assign('future', f, envir = globalenv())
    })
    assign('results', results, envir = globalenv())

    value(results)

  })


}

shinyApp(ui, server)

if(F){
  db <- get('db', envir = environment(future:::FutureRegistry))
  db$`workers-609fd3814c007936f32080cd28167cd7`
}
