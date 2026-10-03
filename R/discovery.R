service_feed <- "https://nedlasting.geonorge.no/geonorge/Tjenestefeed_daglig.xml"
atom_ns <- c(a = "http://www.w3.org/2005/Atom")

official_url <- function(url) {
  scalar_text(url, "Geonorge URL")
  url <- sub("^http://nedlasting.geonorge.no/", "https://nedlasting.geonorge.no/", url)
  if (!grepl("^https://nedlasting[.]geonorge[.]no/", url))
    abort("Unexpected Geonorge download host: ", url)
  url
}

http_get <- function(url, path = NULL) {
  url <- official_url(url)
  request <- httr2::request(url)
  request <- httr2::req_user_agent(request, "kartdata R client")
  request <- httr2::req_timeout(request, if (is.null(path)) 60 else 1800)
  request <- httr2::req_retry(request, max_tries = 3)
  if (!is.null(path) && progress_enabled()) request <- httr2::req_progress(request, type = "down")
  tryCatch(httr2::req_perform(request, path = path), error = function(e)
    abort("Could not retrieve data from Geonorge. Check the network and service availability. ",
          conditionMessage(e)))
}

feed_xml <- function(url) {
  response <- http_get(url)
  tryCatch(xml2::read_xml(httr2::resp_body_raw(response)), error = function(e)
    abort("Invalid Geonorge ATOM response: ", conditionMessage(e)))
}

entries <- function(doc) {
  if (xml2::xml_name(doc) != "feed" ||
      !length(xml2::xml_find_all(doc, "/a:feed", atom_ns)))
    abort("Geonorge response is not an ATOM feed; its schema may have changed.")
  xml2::xml_find_all(doc, "/a:feed/a:entry", atom_ns)
}

child_text <- function(node, name) {
  xml2::xml_text(xml2::xml_find_first(node, paste0("a:", name), atom_ns))
}

product_feeds <- function(doc, series) {
  id <- n_products()$metadata_id[match(series, n_products()$series)]
  result <- lapply(entries(doc), function(e) {
    metadata <- xml2::xml_attr(xml2::xml_find_all(e, "a:link[@rel='describedby']", atom_ns), "href")
    if (!any(grepl(paste0("[?&]id=", id, "($|[& ])"), metadata))) return(NULL)
    title <- child_text(e, "title")
    format <- if (grepl(" FGDB-format$", title)) "FGDB" else if (grepl(" GML-format$", title)) "GML" else return(NULL)
    links <- xml2::xml_attr(xml2::xml_find_all(e, "a:link[@type='application/atom+xml']", atom_ns), "href")
    if (length(links) != 1L || is.na(links)) abort("Unexpected product feed links for ", series, ".")
    data.frame(format = format, feed = official_url(links))
  })
  result <- unique(do.call(rbind, result))
  if (is.null(result) || !nrow(result)) abort("No FGDB/GML feed found for ", series, "; Geonorge metadata may have changed.")
  if (anyDuplicated(result$format)) abort("Ambiguous Geonorge product feeds for ", series, ".")
  result
}

download_entry <- function(doc, area, epsg) {
  rows <- lapply(entries(doc), function(e) {
    crs <- xml2::xml_attr(xml2::xml_find_all(e, "a:category", atom_ns), "term")
    if (!paste0("EPSG:", epsg) %in% crs) return(NULL)
    links <- xml2::xml_attr(xml2::xml_find_all(e, "a:link[@href]", atom_ns), "href")
    links <- links[!is.na(links) & grepl("[.]zip$", links, ignore.case = TRUE)]
    # Area codes are not supplied as structured ATOM fields. Interpret the
    # published file basename, never construct a download URL from this pattern.
    links <- unique(links[grepl(paste0("^[^_]+_", area, "_"), basename(links))])
    if (!length(links)) return(NULL)
    if (length(links) != 1L) abort("Ambiguous archive links in Geonorge ATOM entry.")
    updated <- child_text(e, "updated")
    if (is.na(updated) || !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T", updated))
      abort("Missing or invalid ATOM updated value; Geonorge response may have changed.")
    data.frame(url = official_url(links), updated = updated)
  })
  result <- unique(do.call(rbind, rows))
  if (is.null(result) || !nrow(result)) return(NULL)
  if (nrow(result) != 1L) abort("Ambiguous Geonorge files for area ", area, " and EPSG:", epsg, ".")
  result
}

readable_formats <- function() {
  drivers <- sf::st_drivers()
  c(if (any(drivers$name %in% c("OpenFileGDB", "FileGDB"))) "FGDB",
    if ("GML" %in% drivers$name) "GML")
}

discover <- function(sel) {
  progress_message("Checking Geonorge files for ", sel$series, "...")
  formats <- readable_formats()
  if (sel$format != "auto") formats <- intersect(sel$format, formats)
  if (!length(formats)) abort("Local GDAL cannot read the requested format. Install sf with OpenFileGDB or GML support.")
  feeds <- product_feeds(feed_xml(service_feed), sel$series)
  for (format in formats) {
    feed <- feeds$feed[feeds$format == format]
    if (!length(feed)) next
    file <- download_entry(feed_xml(feed), sel$area, sel$epsg)
    if (!is.null(file)) return(c(sel[c("series", "area", "epsg")],
                                list(format = format, feed = feed, url = file$url, updated = file$updated)))
  }
  abort("No readable Geonorge archive for ", sel$series, ", area ", sel$area,
        ", EPSG:", sel$epsg, ". See n_areas('", sel$series,
        "') for available areas, EPSG codes and formats.")
}
