# Session-local LRU cache. Original files remain the source of truth.
.read_cache <- new.env(parent = emptyenv())
.read_cache$entries <- list()

memory_limit <- function() {
  limit <- getOption("kartdata.memory_cache_size", 128 * 1024^2)
  if (!is.numeric(limit) || length(limit) != 1L || is.na(limit) ||
      !is.finite(limit) || limit < 0)
    abort("Option kartdata.memory_cache_size must be a finite non-negative number of bytes.")
  limit
}

memory_trim <- function(reserve = 0) {
  limit <- memory_limit()
  entries <- .read_cache$entries
  while (length(entries) && sum(vapply(entries, function(x) x$bytes, numeric(1))) + reserve > limit)
    entries <- entries[-1L]
  .read_cache$entries <- entries
  invisible(limit)
}

memory_path <- function(path) {
  result <- normalizePath(path, winslash = "/", mustWork = FALSE)
  if (.Platform$OS.type == "windows") result <- tolower(result)
  result
}

memory_version <- function(cached) {
  files <- file.path(cached$path, c("metadata.dcf", "original.zip", "files.tsv"))
  list(metadata = read_manifest(cached$path),
       stats = unname(as.matrix(file.info(files)[, c("size", "mtime", "ctime")])))
}

memory_forget <- function(path) {
  path <- memory_path(path)
  .read_cache$entries <- Filter(function(x) !identical(x$path, path), .read_cache$entries)
  invisible(NULL)
}

memory_clear <- function(cache_dir, series = NULL) {
  root <- memory_path(cache_root(cache_dir))
  .read_cache$entries <- Filter(function(x) {
    matches <- identical(dirname(x$path), root) &&
      (is.null(series) || startsWith(toupper(basename(x$path)), paste0(series, "_")))
    !matches
  }, .read_cache$entries)
  invisible(NULL)
}

memory_fetch <- function(cached, kind, name, compute, enabled = TRUE) {
  limit <- memory_trim()
  if (!enabled || limit == 0) return(compute())
  path <- memory_path(cached$path)
  version <- memory_version(cached)
  # A new version invalidates both the index and every loaded layer.
  .read_cache$entries <- Filter(function(x)
    !identical(x$path, path) || identical(x$version, version), .read_cache$entries)
  entries <- .read_cache$entries
  hit <- which(vapply(entries, function(x)
    identical(x$path, path) && identical(x$kind, kind) && identical(x$name, name), logical(1)))
  if (length(hit)) {
    item <- entries[[hit]]
    .read_cache$entries <- c(entries[-hit], list(item))
    return(item$value)
  }
  value <- compute()
  bytes <- as.numeric(utils::object.size(value))
  if (bytes <= limit) {
    memory_trim(bytes)
    .read_cache$entries <- c(.read_cache$entries, list(list(
      path = path, version = version, kind = kind, name = name, value = value, bytes = bytes)))
  }
  value
}

cached_layer_index <- function(cached, enabled = TRUE) {
  memory_fetch(cached, "index", "", function()
    layer_index(file.path(cached$path, "files"), cached$format), enabled)
}

memory_info <- function(path) {
  memory_trim()
  path <- memory_path(path)
  entries <- Filter(function(x) identical(x$path, path), .read_cache$entries)
  c(memory_bytes = sum(vapply(entries, function(x) x$bytes, numeric(1))),
    cached_layers = sum(vapply(entries, function(x) identical(x$kind, "layer"), logical(1))))
}
