area_input <- function(area) {
  if (is.numeric(area)) {
    if (length(area) != 1L || is.na(area) || !is.finite(area) ||
        area < 0 || area > 9999 || area != floor(area))
      abort("area must be an area name or an integer code between 0 and 9999.")
    return(if (area == 0) "0000" else sprintf(if (area < 100) "%02d" else "%04d", as.integer(area)))
  }
  area <- trimws(scalar_text(area, "area"))
  if (!nzchar(area) || grepl("[/\\\\\r\n\t]", area)) abort("Invalid area name or code.")
  if (grepl("^[0-9]+$", area)) {
    if (!nchar(area) %in% c(2L, 4L)) abort("Use a two- or four-digit area code, or an area name.")
    return(area)
  }
  if (tolower(area) %in% c("norge", "landsdekkende")) return("0000")
  area
}

area_table <- function(doc, format) {
  rows <- lapply(entries(doc), function(e) {
    links <- xml2::xml_attr(xml2::xml_find_all(e, "a:link[@href]", atom_ns), "href")
    links <- unique(links[!is.na(links) & grepl("[.]zip$", links, ignore.case = TRUE)])
    if (!length(links)) return(NULL)
    categories <- xml2::xml_find_all(e, "a:category", atom_ns)
    terms <- xml2::xml_attr(categories, "term")
    crs <- terms[!is.na(terms) & grepl("^EPSG:[0-9]+$", terms)]
    labels <- xml2::xml_attr(categories[which(terms %in% c("Fylke", "Kommune"))], "label")
    labels <- unique(labels[!is.na(labels) & nzchar(labels)])
    parts <- regmatches(basename(links), regexec("^[^_]+_([0-9]{2}|[0-9]{4})_(.+)_[0-9]+_[^_]+_[^_]+[.]zip$", basename(links), ignore.case = TRUE))
    if (length(links) != 1L || length(parts[[1]]) != 3L || length(crs) != 1L || length(labels) > 1L)
      abort("Cannot identify area in Geonorge ATOM entry; its schema may have changed.")
    code <- parts[[1]][2]
    name <- if (code == "0000") "Norge" else if (length(labels)) labels else gsub("_", " ", utils::URLdecode(parts[[1]][3]))
    data.frame(area = code, name = name, epsg = as.integer(sub("EPSG:", "", crs)), format = format)
  })
  result <- unique(do.call(rbind, rows))
  if (is.null(result) || !nrow(result)) abort("No areas found in Geonorge ATOM feed.")
  result
}

area_catalog_path <- function(series, cache_dir) {
  file.path(cache_root(cache_dir), paste0("areas-", series, ".tsv"))
}

read_area_catalog <- function(path) {
  tryCatch({
    x <- utils::read.delim(path, colClasses = c("character", "character", "integer", "character"),
                         encoding = "UTF-8", check.names = FALSE)
    if (!identical(names(x), c("area", "name", "epsg", "format")) || !nrow(x) || anyNA(x) ||
        any(!grepl("^[0-9]{2}([0-9]{2})?$", x$area)) || any(!nzchar(x$name)) ||
        any(x$epsg < 1) || any(!x$format %in% c("FGDB", "GML"))) return(NULL)
    x
  }, error = function(e) NULL, warning = function(w) NULL)
}

#' Find available download areas
#'
#' Lists published areas and coordinate systems using Geonorge ATOM metadata.
#' No map archives are downloaded. A small UTF-8 table is cached locally for
#' offline name lookup. Use `refresh = TRUE` to update it after area changes.
#'
#' @param series N-series, such as `"N1000"` or `1000`.
#' @param refresh Logical; fetch current metadata instead of reusing the table.
#' @param cache_dir Cache root, as in [n_get()].
#' @return A data frame with `area` (character code), `name`, `epsg` and
#'   `format`. Each row describes a published combination, independent of
#'   local GDAL support. The table is not a complete municipality register.
#' @export
#' @examples
#' \dontrun{
#' areas <- n_areas("N1000")
#' subset(areas, name == "Oslo")
#' veg <- n_get("Veglenke", "N1000", area = "Oslo")
#' }
n_areas <- function(series = "N1000", refresh = FALSE,
                    cache_dir = tools::R_user_dir("kartdata", "cache")) {
  series <- series_name(series)
  if (!is.logical(refresh) || length(refresh) != 1L || is.na(refresh)) abort("refresh must be TRUE or FALSE.")
  path <- area_catalog_path(series, cache_dir)
  if (!refresh && file.exists(path)) {
    cached <- read_area_catalog(path)
    if (!is.null(cached)) return(cached)
  }
  progress_message("Finding available areas for ", series, "...")
  feeds <- product_feeds(feed_xml(service_feed), series)
  rows <- lapply(seq_len(nrow(feeds)), function(i) area_table(feed_xml(feeds$feed[i]), feeds$format[i]))
  result <- unique(do.call(rbind, rows))
  result <- result[order(result$area, result$epsg, result$format), , drop = FALSE]
  rownames(result) <- NULL
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  # Stage a complete table; a failed request never overwrites the old catalog.
  stage <- tempfile(".areas-", tmpdir = dirname(path))
  on.exit(unlink(stage), add = TRUE)
  # write.table escapes non-ASCII names in an ASCII locale. Write explicit
  # UTF-8 bytes with TSV quoting so names also survive headless R sessions.
  columns <- lapply(result, function(x) {
    if (is.numeric(x)) return(as.character(x))
    paste0('"', gsub('"', '""', enc2utf8(x), fixed = TRUE), '"')
  })
  lines <- c(paste(names(result), collapse = "\t"), do.call(paste, c(columns, sep = "\t")))
  writeLines(lines, stage, useBytes = TRUE)
  if (!file.copy(stage, path, overwrite = TRUE)) abort("Cannot save area catalog: ", path)
  result
}

resolve_area <- function(sel, refresh, cache_dir) {
  if (grepl("^[0-9]{2}([0-9]{2})?$", sel$area)) return(sel$area)
  areas <- n_areas(sel$series, refresh = refresh != "never", cache_dir = cache_dir)
  matches <- unique(areas$area[tolower(areas$name) == tolower(sel$area)])
  if (length(matches) == 1L) return(matches)
  if (length(matches) > 1L) abort("Ambiguous area '", sel$area, "'. Choose a code: ", paste(matches, collapse = ", "), ". See n_areas().")
  choices <- unique(areas[, c("area", "name")])
  close <- agrep(sel$area, choices$name, ignore.case = TRUE, max.distance = 0.3)
  if (length(close)) choices <- choices[close, , drop = FALSE]
  choices <- utils::head(choices, 12)
  abort("Unknown area '", sel$area, "'. Available names include: ",
        paste(paste0(choices$name, " (", choices$area, ")"), collapse = ", "),
        ". See n_areas('", sel$series, "') for all published areas.")
}
