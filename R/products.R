#' Available topographic products
#'
#' @return A data frame with series, scale and Geonorge metadata identifiers.
#' @export
#' @examples
#' n_products()
n_products <- function() {
  data.frame(
    series = paste0("N", c(50, 100, 250, 500, 1000, 2000, 5000)),
    scale = c(50000, 100000, 250000, 500000, 1000000, 2000000, 5000000),
    metadata_id = c(
      "ea192681-d039-42ec-b1bc-f3ce04c189ac",
      "11a70876-5b21-4cc6-8229-902266c4968f",
      "442cae64-b447-478d-b384-545bc1d9ab48",
      "58e0dbf8-0d47-47c8-8086-107a3fa2dfa4",
      "aee42bb6-d0e9-4d70-86fe-6ea76c381055",
      "8d52075d-6ef6-4120-8041-d0c0901f21f7",
      "c777d53d-8916-4d9d-bae4-6d5140e0c569"
    )
  )
}

abort <- function(...) stop(..., call. = FALSE)

scalar_text <- function(x, name) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x))
    abort(name, " must be a non-empty string.")
  x
}

series_name <- function(series) {
  if (is.numeric(series) && length(series) == 1L) series <- as.character(series)
  series <- toupper(scalar_text(series, "series"))
  if (!startsWith(series, "N")) series <- paste0("N", series)
  if (!series %in% n_products()$series)
    abort("Unknown N-series: ", series, ". Choose ", paste(n_products()$series, collapse = ", "), ".")
  series
}

selection <- function(series, area, epsg, format) {
  series <- series_name(series)
  scalar_text(area, "area")
  if (!grepl("^[0-9]{2}([0-9]{2})?$", area))
    abort("area must be a character code, e.g. '0000' (Norway) or '03' (Oslo).")
  if (!is.numeric(epsg) || length(epsg) != 1L || is.na(epsg) ||
      !is.finite(epsg) || epsg < 1 || epsg != floor(epsg)) abort("epsg must be a positive integer.")
  format <- match.arg(format, c("auto", "FGDB", "GML"))
  list(series = series, area = area, epsg = epsg, format = format)
}
