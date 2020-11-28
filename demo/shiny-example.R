library(future)
library(futurenow)
library(shiny)

## uncomment to enable debugging
# options('future.debug' = TRUE)
# futurenow::debug_futurenow('.debug.log', reset = TRUE, master_only = FALSE)

ui <- fluidPage(
  actionButton("ok", "Run")
)

server <- function(input, output, session) {

  observeEvent(input$ok, {
    p <- Progress$new(session = session, min = 0, max = 10)
    plan(futurenow)

    on.exit({
      p$close()
      plan(sequential)
    }, add = TRUE)

    futurenow_lapply(1:10, function(i){
      # Run something async

      # Run in master session
      run_in_master({
        p$inc(amount = 1, message = 'Running item',
                         detail = sprintf('Processing %d', i))
      }, local_vars = 'i')

      # Run something async again
    })

  })


}

shinyApp(ui, server)
