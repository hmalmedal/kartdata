cache_root <- function(cache_dir) {
  scalar_text(cache_dir, "cache_dir")
  file.path(path.expand(cache_dir), "downloads-v1")
}

cache_key <- function(sel, format = sel$format) {
  paste(sel$series, sel$area, sel$epsg, format, sep = "_")
}

read_manifest <- function(path) {
  tryCatch({
    x <- read.dcf(file.path(path, "metadata.dcf"))
    required <- c("series", "area", "epsg", "format", "url", "updated", "downloaded", "bytes", "md5")
    if (nrow(x) != 1L || !all(required %in% colnames(x))) return(NULL)
    as.list(x[1, ])
  }, error = function(e) NULL)
}

cache_valid <- function(path, verify = FALSE) {
  meta <- read_manifest(path)
  if (is.null(meta)) return(FALSE)
  archive <- file.path(path, "original.zip")
  if (!file.exists(archive) || is.na(suppressWarnings(as.numeric(meta$bytes))) ||
      file.info(archive)$size != as.numeric(meta$bytes)) return(FALSE)
  inventory <- tryCatch(utils::read.delim(file.path(path, "files.tsv"),
                                        stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(inventory) || !all(c("name", "size") %in% names(inventory)) || !nrow(inventory)) return(FALSE)
  if (any(!safe_members(inventory$name))) return(FALSE)
  sizes <- file.info(file.path(path, "files", inventory$name))$size
  if (anyNA(sizes) || !identical(as.numeric(sizes), as.numeric(inventory$size))) return(FALSE)
  if (verify) {
    progress_message("Verifying archive checksum for ", meta$series, " (", meta$format, ")...")
    if (!identical(unname(tools::md5sum(archive)), meta$md5)) return(FALSE)
  }
  TRUE
}

safe_members <- function(names) {
  !is.na(names) & nzchar(names) &
    !grepl("(^[/\\\\])|(^[A-Za-z]:)|(^|[/\\\\])[.][.]([/\\\\]|$)", names)
}

unpack_archive <- function(archive, directory) {
  progress_message("Unpacking Geonorge archive...")
  listing <- tryCatch(utils::unzip(archive, list = TRUE), error = function(e)
    abort("Corrupt or incomplete Geonorge ZIP: ", conditionMessage(e)))
  if (!nrow(listing) || any(!safe_members(listing$Name))) abort("Invalid or unsafe Geonorge ZIP archive.")
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  tryCatch(withCallingHandlers(utils::unzip(archive, exdir = directory),
                              warning = function(w) abort("Cannot unpack Geonorge ZIP: ", conditionMessage(w))),
           error = function(e) abort("Corrupt or incomplete Geonorge ZIP: ", conditionMessage(e)))
  files <- listing[!grepl("[/\\\\]$", listing$Name), , drop = FALSE]
  sizes <- file.info(file.path(directory, files$Name))$size
  if (!nrow(files) || anyNA(sizes) || any(sizes != files$Length))
    abort("Incomplete Geonorge ZIP extraction; cached data were not replaced.")
  data.frame(name = files$Name, size = sizes)
}

ensure_cache <- function(sel, refresh, cache_dir) {
  root <- cache_root(cache_dir)
  formats <- if (sel$format == "auto") readable_formats() else intersect(sel$format, readable_formats())
  if (!length(formats)) abort("Local GDAL cannot read the requested format. Install sf with OpenFileGDB or GML support.")
  candidates <- file.path(root, vapply(formats, function(f) cache_key(sel, f), character(1)))
  existing <- candidates[dir.exists(candidates)]
  if (length(existing) && refresh == "never") {
    path <- existing[1]
    if (!cache_valid(path)) abort("Corrupt or incomplete cache at ", path, ". Use refresh = 'force'.")
    meta <- read_manifest(path)
    return(list(path = path, format = meta$format))
  }
  remote <- discover(sel)
  target <- file.path(root, cache_key(remote))
  if (refresh == "check" && dir.exists(target) && cache_valid(target)) {
    meta <- read_manifest(target)
    if (identical(meta$url, remote$url) && identical(meta$updated, remote$updated))
      return(list(path = target, format = remote$format))
  }
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  lock <- paste0(target, ".lock")
  if (!dir.create(lock, showWarnings = FALSE))
    abort("Cache is locked by another download: ", lock, ". If a previous R process crashed, remove this empty lock directory after checking that no download is running.")
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  stage <- tempfile(".download-", tmpdir = root)
  dir.create(stage)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)
  archive <- file.path(stage, "original.zip")
  progress_message("Downloading ", remote$series, " (", remote$format, ", area ", remote$area, ") from Geonorge...")
  http_get(remote$url, path = archive)
  inventory <- unpack_archive(archive, file.path(stage, "files"))
  source_layers(file.path(stage, "files"), remote$format)
  progress_message("Calculating archive checksum and saving cache...")
  meta <- c(remote, list(downloaded = format(Sys.time(), tz = "UTC", usetz = TRUE),
                         bytes = as.character(file.info(archive)$size),
                         md5 = unname(tools::md5sum(archive))))
  write.dcf(as.data.frame(meta, stringsAsFactors = FALSE), file.path(stage, "metadata.dcf"))
  utils::write.table(inventory, file.path(stage, "files.tsv"), sep = "\t", row.names = FALSE, quote = TRUE)
  # Keep the old version until the complete replacement has passed validation.
  backup <- tempfile(".previous-", tmpdir = root)
  had_old <- dir.exists(target)
  if (had_old && !file.rename(target, backup)) abort("Cannot replace cache; close applications using ", target)
  if (!file.rename(stage, target)) {
    if (had_old) file.rename(backup, target)
    abort("Cannot publish downloaded cache at ", target)
  }
  memory_forget(target)
  if (had_old) unlink(backup, recursive = TRUE)
  progress_message("Download cache ready for ", remote$series, ".")
  list(path = target, format = remote$format)
}

cache_paths <- function(cache_dir, series = NULL) {
  root <- cache_root(cache_dir)
  if (!dir.exists(root)) return(character())
  paths <- list.dirs(root, recursive = FALSE, full.names = TRUE)
  pattern <- "^N(50|100|250|500|1000|2000|5000)_[0-9]{2}([0-9]{2})?_[0-9]+_(FGDB|GML)$"
  paths <- paths[grepl(pattern, basename(paths))]
  if (!is.null(series)) paths <- paths[startsWith(basename(paths), paste0(series_name(series), "_"))]
  paths
}

#' Inspect or clear the local map cache
#'
#' Progress messages for network checks and checksum verification follow
#' `options(kartdata.progress)`, defaulting to `interactive()`.
#'
#' @param series Optional series filter; `NULL` selects all series.
#' @param cache_dir Cache root; defaults to the standard R user cache.
#' @param check If TRUE, contact Geonorge to compare each cached version with
#'   the current ATOM entry. Does not download map data. Network failures error.
#' @param verify If TRUE, also verify the original ZIP checksum. Otherwise
#'   check the presence and sizes of the ZIP and extracted files.
#' @param memory_only If TRUE, clear only the selected session memory entries;
#'   retain downloaded files. Default FALSE clears both memory and disk.
#' @return `n_cache_info()` returns a data frame with paths, version metadata,
#'   sizes, integrity status and (when checked) whether updates are available.
#'   `memory_bytes` counts approximate retained object sizes (including the
#'   layer index); `cached_layers` counts retained sf layers in this R session.
#'   `n_cache_clear()` invisibly returns the removed cache paths.
#' @export
#' @examples
#' n_cache_info()
#' \dontrun{
#' n_cache_info(check = TRUE)
#' n_cache_clear("N1000")
#' }
n_cache_info <- function(series = NULL, cache_dir = tools::R_user_dir("kartdata", "cache"),
                         check = FALSE, verify = FALSE) {
  if (!is.logical(check) || length(check) != 1L || is.na(check) ||
      !is.logical(verify) || length(verify) != 1L || is.na(verify)) abort("check and verify must be TRUE or FALSE.")
  if (!is.null(series)) series <- series_name(series)
  paths <- cache_paths(cache_dir, series)
  empty <- data.frame(series = character(), area = character(), epsg = integer(),
                      format = character(), updated = character(), downloaded = character(),
                      bytes = numeric(), valid = logical(), update_available = logical(), path = character(),
                      memory_bytes = numeric(), cached_layers = integer())
  if (!length(paths)) return(empty)
  rows <- lapply(paths, function(path) {
    parts <- strsplit(basename(path), "_", fixed = TRUE)[[1]]
    meta <- read_manifest(path)
    current <- NA
    if (check && !is.null(meta)) {
      remote <- discover(selection(parts[1], parts[2], as.numeric(parts[3]), parts[4]))
      current <- !identical(meta$updated, remote$updated) || !identical(meta$url, remote$url)
    }
    memory <- memory_info(path)
    data.frame(series = parts[1], area = parts[2], epsg = as.integer(parts[3]), format = parts[4],
               updated = if (is.null(meta)) NA_character_ else meta$updated,
               downloaded = if (is.null(meta)) NA_character_ else meta$downloaded,
               bytes = sum(file.info(list.files(path, recursive = TRUE, full.names = TRUE))$size),
               valid = cache_valid(path, verify), update_available = current, path = path,
               memory_bytes = unname(memory["memory_bytes"]), cached_layers = as.integer(memory["cached_layers"]))
  })
  do.call(rbind, rows)
}

#' @rdname n_cache_info
#' @export
n_cache_clear <- function(series = NULL, cache_dir = tools::R_user_dir("kartdata", "cache"),
                          memory_only = FALSE) {
  if (!is.null(series)) series <- series_name(series)
  if (!is.logical(memory_only) || length(memory_only) != 1L || is.na(memory_only))
    abort("memory_only must be TRUE or FALSE.")
  memory_clear(cache_dir, series)
  if (memory_only) return(invisible(character()))
  paths <- cache_paths(cache_dir, series)
  root <- normalizePath(cache_root(cache_dir), winslash = "/", mustWork = FALSE)
  for (path in paths) {
    resolved <- normalizePath(path, winslash = "/", mustWork = TRUE)
    if (!identical(dirname(resolved), root)) abort("Refusing to clear a cache path outside the cache root: ", path)
    if (dir.exists(paste0(path, ".lock"))) abort("Cache is in use: ", path)
    if (unlink(path, recursive = TRUE) != 0L) abort("Could not remove cache: ", path)
  }
  invisible(paths)
}
