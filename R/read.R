source_layers <- function(directory, format) {
  sources <- if (format == "FGDB") {
    dirs <- list.dirs(directory, recursive = TRUE, full.names = TRUE)
    dirs[grepl("[.]gdb$", dirs, ignore.case = TRUE)]
  } else {
    list.files(directory, "[.]gml$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
  }
  if (!length(sources)) abort("Incomplete cache: no ", format, " data source found. Use refresh = 'force'.")
  rows <- lapply(sources, function(source) {
    layers <- tryCatch(sf::st_layers(source, do_count = FALSE), error = function(e)
      abort("GDAL cannot list layers; cache may be corrupt or the driver unsupported. ", conditionMessage(e)))
    data.frame(layer = layers$name, source = source, stringsAsFactors = FALSE)
  })
  result <- do.call(rbind, rows)
  if (!nrow(result)) abort("No layers found in the cached dataset. Use refresh = 'force'.")
  result
}

sql_identifier <- function(x) paste0('"', gsub('"', '""', x, fixed = TRUE), '"')
sql_string <- function(x) paste0("'", gsub("'", "''", x, fixed = TRUE), "'")

layer_index <- function(directory, format) {
  physical <- source_layers(directory, format)
  physical$physical <- physical$layer
  physical$filter <- NA_character_
  if (format != "FGDB") return(physical)
  # FGDB groups object types by theme and geometry. Ask GDAL for attributes
  # only, then let GDAL filter the one requested object type during the read.
  logical <- lapply(seq_len(nrow(physical)), function(i) {
    row <- physical[i, , drop = FALSE]
    query <- paste0("SELECT DISTINCT objtype FROM ", sql_identifier(row$physical))
    types <- tryCatch(sf::st_read(row$source, query = query, quiet = TRUE),
                      error = function(e) abort("Cannot discover FGDB object types. Try format = 'GML'. ", conditionMessage(e)))
    if (!"objtype" %in% names(types)) abort("FGDB schema has changed: missing objtype. Try format = 'GML'.")
    values <- unique(as.character(types$objtype))
    values <- values[!is.na(values) & nzchar(values)]
    if (!length(values)) return(NULL)
    data.frame(layer = values, source = row$source, physical = row$physical, filter = values)
  })
  logical <- do.call(rbind, logical)
  if (is.null(logical)) return(physical)
  # Keep original physical names available for ambiguous object types.
  rbind(logical, physical)
}

#' List or read topographic layers
#'
#' Original archives are cached outside the project. The first call downloads
#' the selected archive (potentially large for detailed series). Only the
#' requested layer is loaded as an sf object. Original names, attributes, dates,
#' identifiers and coordinate reference system are preserved as read by GDAL.
#' Layer indexes and loaded objects are reused in this R session, with a shared
#' approximate 128 MiB LRU limit. Set `options(kartdata.memory_cache_size = 0)`
#' to disable all memory caching, or supply another limit in bytes. Objects
#' larger than the limit are returned without being retained. Updating or
#' clearing the disk cache invalidates its memory entries.
#'
#' @param series N-series, such as `"N1000"` or `1000`.
#' @param area Character area code; `"0000"` selects nationwide data.
#' @param epsg EPSG code of the published file, default 25833. This selects a
#'   download; it does not reproject data.
#' @param format `"auto"` prefers FGDB when available and locally readable,
#'   otherwise GML. Can also be `"FGDB"` or `"GML"`. FGDB object types are
#'   exposed as logical layers using GDAL SQL on the original `objtype` field;
#'   original physical layer names are also available.
#' @param refresh `"never"` reuses cache without network access (default),
#'   `"check"` checks ATOM URL and updated value, `"force"` downloads again.
#'   A missing cache is downloaded in every mode.
#' @param cache_dir Cache root; defaults to `tools::R_user_dir("kartdata", "cache")`.
#' @param layer Exact layer name returned by `n_layers()`.
#' @param memory_cache If TRUE (default), reuse and retain the layer and its
#'   index in session memory. FALSE bypasses both for this call.
#' @return `n_layers()` returns a character vector; `n_get()` an `sf` object.
#' @export
#' @examples
#' \dontrun{
#' n_layers("N1000")
#' veg <- n_get("Veglenke", "N1000")
#' plot(sf::st_geometry(veg))
#' }
n_layers <- function(series = "N1000", area = "0000", epsg = 25833,
                     format = c("auto", "FGDB", "GML"),
                     refresh = c("never", "check", "force"),
                     cache_dir = tools::R_user_dir("kartdata", "cache")) {
  sel <- selection(series, area, epsg, match.arg(format))
  cached <- ensure_cache(sel, match.arg(refresh), cache_dir)
  sort(unique(cached_layer_index(cached)$layer))
}

#' @rdname n_layers
#' @export
n_get <- function(layer, series = "N1000", area = "0000", epsg = 25833,
                  format = c("auto", "FGDB", "GML"),
                  refresh = c("never", "check", "force"),
                  cache_dir = tools::R_user_dir("kartdata", "cache"),
                  memory_cache = TRUE) {
  scalar_text(layer, "layer")
  if (!is.logical(memory_cache) || length(memory_cache) != 1L || is.na(memory_cache))
    abort("memory_cache must be TRUE or FALSE.")
  sel <- selection(series, area, epsg, match.arg(format))
  cached <- ensure_cache(sel, match.arg(refresh), cache_dir)
  memory_fetch(cached, "layer", layer, function() read_layer(layer, cached, memory_cache), memory_cache)
}

read_layer <- function(layer, cached, memory_cache) {
  layers <- cached_layer_index(cached, enabled = memory_cache)
  chosen <- layers[layers$layer == layer, , drop = FALSE]
  if (!nrow(chosen)) abort("Unknown layer '", layer, "'. Available layers: ",
                            paste(sort(unique(layers$layer)), collapse = ", "))
  if (nrow(chosen) != 1L) abort("Layer name is ambiguous across data sources: ", layer,
                              ". Choose a physical layer: ", paste(unique(chosen$physical), collapse = ", "))
  query <- if (!is.na(chosen$filter)) paste0("SELECT * FROM ", sql_identifier(chosen$physical),
                                            " WHERE objtype = ", sql_string(chosen$filter)) else NULL
  tryCatch(if (is.null(query)) sf::st_read(chosen$source, layer = chosen$physical, quiet = TRUE)
           else sf::st_read(chosen$source, query = query, quiet = TRUE), error = function(e)
    abort("GDAL could not read layer '", layer, "'. Try refresh = 'force' or format = 'GML'. ", conditionMessage(e)))
}
