find_globals <- function(expr, env = parent.frame(), ...){
  future::getGlobalsAndPackages(expr = expr, envir = env, ...)
}

tweakExpr_run_in_master <- function(expr){
  if(!is.language(expr)) {
    return(expr)
  }
  if(expr[[1]] == quote(run_in_master)){

    if(length(as.list(expr)) == 1){
      return(quote({}))
    }

    expr <- expr[[2]]

    # find register_name
    ignore_list <- list(quote(`{`))
    globals::walkAST(expr, call = function(expr){
      if(!is.language(expr) || length(as.list(expr)) == 1 || expr[[1]] != quote(register_name)) {
        return(expr)
      }
      ignore_list[[length(ignore_list) + 1]] <<- as.call(list(quote(`<-`), expr[[2]], 1))
    })
    return(as.call(ignore_list))
  }
  return(expr)
}

tweakExpr_register_name <- function(expr){
  if(!is.language(expr)) {
    return(expr)
  }
  if(expr[[1]] == quote(register_name)){
    return()
  }
  return(expr)
}

tweakExpression_futurenow <- function(expr){
  if(!is.language(expr)) {
    return(expr)
  }
  expr <- globals::walkAST(expr, call = tweakExpr_run_in_master)
  expr <- globals::walkAST(expr, call = tweakExpr_register_name)
  return(expr)
}

