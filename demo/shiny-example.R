library(future)
library(futurenow)
library(shiny)
# debug_futurenow(tmpfile = stdout(), reset = TRUE, master_only = TRUE)
options("future.debug" = TRUE)
ui <- fluidPage(
  actionButton("ok", "Run")
)

server <- function(input, output, session) {

  futurenow:::shiny_futurenow_init(session = session)

  observeEvent(input$ok, {
    plan('multisession')

    p <- Progress$new(session = session, min = 0, max = 10)

    # FIXME: more than 4 futures will block the main session
    results <- lapply(1:10, function(i){

      futurenow({
        # Run something
        Sys.sleep(1)
        # inc progress bar
        run_in_master({
          p$inc(amount = 1, message = 'Running item', detail = i)
        })
      })
    })
    value(results)

    p$clone()
  })
}

shinyApp(ui, server)
