progress_enabled <- function() {
  enabled <- getOption("kartdata.progress", interactive())
  if (!is.logical(enabled) || length(enabled) != 1L || is.na(enabled))
    abort("Option kartdata.progress must be TRUE or FALSE.")
  enabled
}

progress_message <- function(...) {
  if (progress_enabled()) message(...)
  invisible(NULL)
}

# Counts completed operations, not estimated time. Always close on exit so
# failed GDAL calls cannot leave an unfinished terminal line behind.
progress_counter <- function(total, label) {
  if (!progress_enabled()) return(list(update = function(value) NULL, close = function() NULL))
  message(label)
  bar <- utils::txtProgressBar(min = 0, max = total, initial = 0,
                                style = 3, file = stderr())
  list(update = function(value) utils::setTxtProgressBar(bar, value),
       close = function() close(bar))
}
