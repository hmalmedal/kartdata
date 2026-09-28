atom <- function(body) xml2::read_xml(paste0(
  '<feed xmlns="http://www.w3.org/2005/Atom">', body, '</feed>'))

service_fixture <- function(formats = c("FGDB", "GML")) {
  atom(paste(vapply(formats, function(fmt) paste0(
    '<entry><title>N1000 Kartdata ', fmt, '-format</title>',
    '<link rel="describedby" href="https://example.org/?id=aee42bb6-d0e9-4d70-86fe-6ea76c381055"/>',
    '<link type="application/atom+xml" href="http://nedlasting.geonorge.no/', fmt, '.xml"/></entry>'), character(1)), collapse = ""))
}

file_fixture <- function(updated = "2026-09-26T23:52:40", area = "0000") {
  atom(paste0('<entry><category term="EPSG:25833"/><updated>', updated,
              '</updated><link rel="alternate" type="application/gml+xml" href="https://nedlasting.geonorge.no/Basisdata_',
              area, '_Norge_25833_N1000Kartdata_FGDB.zip"/></entry>'))
}

mock_discovery <- function(updated = "2026-09-26T23:52:40") {
  local_mocked_bindings(
    feed_xml = function(url) if (identical(url, service_feed)) service_fixture() else file_fixture(updated),
    readable_formats = function() c("FGDB", "GML"), .package = "kartdata", .env = parent.frame())
}

small_archive <- function(format = "GML") {
  work <- tempfile("kartdata-fixture-")
  dir.create(work)
  if (format == "FGDB") {
    dsn <- file.path(work, "tiny.gdb")
    layer <- "N1000_Samferdsel_senterlinje"
    driver <- "OpenFileGDB"
  } else {
    dsn <- file.path(work, "tiny.gml")
    layer <- "Veglenke"
    driver <- "GML"
  }
  data <- sf::st_sf(objtype = c("Veglenke", "Bane"), kommunenummer = c("0301", "0301"),
                    geometry = sf::st_sfc(sf::st_linestring(matrix(c(0, 0, 1, 1), 2, byrow = TRUE)),
                                          sf::st_linestring(matrix(c(2, 2, 3, 3), 2, byrow = TRUE)), crs = 25833))
  sf::st_write(data, dsn, layer = layer, driver = driver, quiet = TRUE)
  archive <- tempfile(fileext = ".zip")
  # zip is already a dependency of testthat; keep it optional for fixtures.
  if (requireNamespace("zip", quietly = TRUE)) {
    zip::zipr(archive, list.files(work, full.names = TRUE), root = work)
  } else {
    old <- setwd(work)
    on.exit(setwd(old), add = TRUE)
    utils::zip(archive, list.files(work, recursive = TRUE), flags = "-q")
  }
  unlink(work, recursive = TRUE)
  archive
}
