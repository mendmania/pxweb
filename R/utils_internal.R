#' Build a path from character elements
#' 
#' This function takes a list of strings and builds a URL to the PX-web API \emph{in reverser order}.
#' 
#' @param varname A character string or a list of strings of the variable(s) in the web API. This can be a data node or a tree node.
#' @param topnodes A string or a list of strings containing the top nodes \emph{in top-to-bottom order}
#' @param baseURL The base URL to use, depending on the web service.
#' @param ... Further arguments passed to  \code{base_url()}.

buildPath <- function(varname, topnodes = NULL, baseURL, ...) {
	
	# Error handling
	if (!is.null(topnodes)) {
	   if (identical(topnodes, ""))
	      stop("ERROR: Internal function pxweb::buildPath: `topnodes` argument set to empty string\n
			 The `topnodes` argument is required to be either NULL or a value or a vector other than [''] interpretable as a character string by paste().\n")
	}
	   
	   # Clean URL string: remove trailing slash
	base <- str_replace_all(baseURL,"/$","")
	
	# Clean topnodes string: Remove whitespace and leading/trailing slashes
	topnodes <- str_trim(topnodes)
	topnodes <- str_replace_all(topnodes,"^/|/$","")
	
	# Build a vector, in the right order, for the URL elements
	urlElements <- paste(c(base,topnodes), collapse="/")
	
	# Create full path and return it
	return(
		paste(urlElements,varname, sep="/")
	)
}



#' Get content from response
#' 
#' Get the content from a response object
#' 
#' @param response response object
#' @param type type format
#' 
getContent <- function(response, type = "csv") {
    
    if (!class(response) == "response") {
        stop("needs to be an response class object")
    }
    
    # Convert to character
    content <- httr::content(response)
    
    if (type == "csv") {
        content <- read.table(
            textConnection(content), 
            sep = ",", 
            header = T, 
            stringsAsFactors = F
        )
    } else {
        stop("Unsupported type format")
    }
    
    return(content)
}




#' Creates a timer that keeps track of how many calls that has been called during
#' a time period depending on the api configuration. If there can't be another call
#' the function pauses R to do the call. 
#' 
#' Use this before function that uses api calls.
#' 
#' @param api_url The url to be passed to \link{api_parameters} to get api_configs.
#' @param calls The number of calls that the functions should count per function call. Default is one.
#' 
#' @examples 
#' url <- base_url("sweSCB", "v1", "sv")
#' api_timer(url)

api_timer <- function(api_url, calls = 1){
  
  api_timestamp_file <- paste(tempdir(), "api_time_stamp.Rdata", sep="/")
  
  if(!file.exists(api_timestamp_file)){ # File doesn't exist
    api_timer <- list(config = pxweb::api_parameters(api_url), 
                      calls = rep(Sys.time(), calls))
    save(api_timer, file=api_timestamp_file)
  } else { # File exist
    load(api_timestamp_file)
    api_timer$calls <- c(api_timer$calls, Sys.time())
    if(length(api_timer$calls) >= api_timer$config$calls_per_period){
      diff <- as.numeric(api_timer$calls[length(api_timer$calls)] - api_timer$calls[1], units="secs")
      Sys.sleep(time=max(api_timer$config$period_in_seconds - diff,0))
      api_timer$calls <- api_timer$calls[as.numeric(Sys.time() - api_timer$calls, units="secs") < api_timer$config$period_in_seconds]
    }
    save(api_timer, file=api_timestamp_file)
  }
}





#' The function takes an url and a dims object and calculates if this needs to
#' be downloaded in batches due to download limit restrictions in the pxweb api.
#' If '*' is used it will get the numberof values for this dimension using a 
#' get_pxweb_metadata call.
#' 
#' @param url The url to download from.
#' @param dims The dimension object to use for downloading
#' 
#' @examples
#' url = "http://api.scb.se/OV0104/v1/doris/sv/ssd/BE/BE0101/BE0101A/BefolkningNy"
#' dims = list(Region = c('*'), Civilstand = c('*'), Alder = '1', Kon = c('*'), 
#'             ContentsCode = c('*'), Tid = c('*'))
#' batches <- create_batch_list(url, dims)
#' 
#' url = "http://api.scb.se/OV0104/v1/doris/sv/ssd/PR/PR0101/PR0101E/Basbeloppet",
#' dims = list(ContentsCode = c('*'),
#'             Tid = c('*'))
#' batches <- create_batch_list(url, dims)
#' 
create_batch_list <- function(url, dims){
  
  starred_dim <- logical(length(dims))
  dim_length <- integer(length(dims))
  names(dim_length) <- names(starred_dim) <- names(dims)
  for(d in seq_along(dims)){ # d <- 3
    if(length(dims[[d]]) == 1 && str_detect(string=dims[[d]], "\\*")) starred_dim[d] <- TRUE
    dim_length[d] <- length(dims[[d]])
  }
  if(any(starred_dim)) {
    node <- get_pxweb_metadata(url)
    alldims <- suppressMessages(get_pxweb_dims(node))
    for(d in which(starred_dim)){
      dim_length[d] <- length(alldims[[names(dim_length)[d]]]$values)
    }
  } else {
    node <- NULL
  }

  # Get api parameters
  api_param <- api_parameters(url)
  
  # Calculate current chunk size
  chunk_size <- prod(dim_length)
  if(chunk_size > api_param$max_values_to_download){
    # Calculate bathces and bathc sizes
    arg_max <- which.max(dim_length)
    batch_size <- floor(dim_length[arg_max] / chunk_size * api_param$max_values_to_download)
    if(batch_size == 0) stop("Too large query! This should not happen, please send the api call to the maintainer.", call.=FALSE)
    no_batch <- dim_length[arg_max] %/% batch_size
    if(dim_length[arg_max] %% batch_size != 0) no_batch + 1    
    message("This is a large query. The data will be downloaded in ",no_batch," batches.")
    # Create list with calls
    batch_list <- list(url=url, dims=list(), content_node=node)
    for (b in 1:no_batch){ # b <- 1
      batch_values_index <- ((b-1)*batch_size+1):min((b*batch_size), dim_length[arg_max])
      batch_values <- alldims[[names(dim_length)[arg_max]]]$values[batch_values_index]
      batch_list$dims[[b]] <- dims
      batch_list$dims[[b]][[names(dim_length[arg_max])]] <- batch_values
    }
  } else {
    batch_list <- list(url=url, dims=list(dims=dims), content_node=node)
  }
  
  return(batch_list)
  
}
 