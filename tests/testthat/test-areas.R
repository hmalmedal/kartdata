area_fixture <- function() {
  atom(paste0(
    '<entry><category term="EPSG:25833"/><link href="https://nedlasting.geonorge.no/Basisdata_0000_Norge_25833_N1000Kartdata_FGDB.zip"/></entry>',
    '<entry><category term="EPSG:25832"/><category term="Fylke" label="Oslo"/><link href="https://nedlasting.geonorge.no/Basisdata_03_Oslo_25832_N1000Kartdata_FGDB.zip"/></entry>',
    '<entry><category term="EPSG:25833"/><category term="Fylke" label="Oslo"/><link href="https://nedlasting.geonorge.no/Basisdata_03_Oslo_25833_N1000Kartdata_FGDB.zip"/></entry>'))
}

test_that("area names and numeric codes are validated without changing EPSG", {
  expect_identical(area_input(3), "03")
  expect_identical(area_input(301), "0301")
  expect_identical(area_input(0), "0000")
  expect_identical(area_input("0301"), "0301")
  expect_identical(area_input("  Oslo  "), "Oslo")
  expect_identical(area_input("NORGE"), "0000")
  expect_identical(area_input("landsdekkende"), "0000")
  expect_equal(selection(1000, "Oslo", 25833, "auto")$epsg, 25833)
  for (x in list(NA, -1, Inf, 3.5, c(3, 11), " ", "../Oslo", "3", "12345"))
    expect_error(area_input(x), "area")
})

test_that("published combinations come from ATOM names, codes and categories", {
  table <- area_table(area_fixture(), "FGDB")
  expect_equal(table$area, c("0000", "03", "03"))
  expect_equal(table$name, c("Norge", "Oslo", "Oslo"))
  expect_equal(table$epsg, c(25833L, 25832L, 25833L))
  expect_true(all(table$format == "FGDB"))
  expect_error(area_table(atom('<entry><link href="https://nedlasting.geonorge.no/new.zip"/></entry>'), "FGDB"), "schema")
})

test_that("area metadata is reused offline, refreshed and cleared by series", {
  cache <- tempfile("kartdata-areas-")
  on.exit(unlink(cache, recursive = TRUE))
  calls <- 0L
  local_mocked_bindings(feed_xml = function(url) {
    calls <<- calls + 1L
    if (identical(url, service_feed)) service_fixture() else area_fixture()
  })
  first <- n_areas(1000, cache_dir = cache)
  expect_equal(nrow(first), 6)
  expect_identical(n_areas(1000, cache_dir = cache), first)
  expect_equal(calls, 3L)
  n_areas(1000, refresh = TRUE, cache_dir = cache)
  expect_equal(calls, 6L)
  local_mocked_bindings(feed_xml = function(...) stop("offline"))
  expect_identical(resolve_area(selection(1000, "oSLo", 25833, "auto"), "never", cache), "03")
  expect_error(resolve_area(selection(1000, "Osloo", 25833, "auto"), "never", cache), "Oslo \\(03\\)")
  expect_error(n_areas(1000, refresh = TRUE, cache_dir = cache), "offline")
  expect_identical(n_areas(1000, cache_dir = cache), first)
  path <- area_catalog_path("N1000", cache)
  n_cache_clear("N50", cache)
  expect_true(file.exists(path))
  n_cache_clear("N1000", cache, memory_only = TRUE)
  expect_true(file.exists(path))
  n_cache_clear("N1000", cache)
  expect_false(file.exists(path))
})

test_that("ambiguous names require codes and never silently choose an area", {
  local_mocked_bindings(n_areas = function(...) data.frame(area = c("03", "0301"), name = c("Oslo", "Oslo")))
  expect_error(resolve_area(selection(1000, "Oslo", 25833, "auto"), "never", tempdir()), "Ambiguous.*03, 0301")
  expect_identical(resolve_area(selection(1000, "03", 25833, "auto"), "never", tempdir()), "03")
})

test_that("UTF-8 names and leading zero codes survive cached table round trips", {
  cache <- tempfile("kartdata-utf8-areas-")
  on.exit(unlink(cache, recursive = TRUE))
  doc <- atom(paste0('<entry><category term="EPSG:25833"/><category term="Kommune" label="V\u00e5ler"/>',
                     '<link href="https://nedlasting.geonorge.no/Basisdata_0311_Valer_25833_N100Kartdata_GML.zip"/></entry>'))
  local_mocked_bindings(feed_xml = function(url) if (identical(url, service_feed)) service_fixture("GML") else doc)
  first <- n_areas(1000, cache_dir = cache)
  expect_identical(first$name, "V\u00e5ler")
  expect_identical(n_areas(1000, cache_dir = cache), first)
  expect_identical(first$area, "0311")
  writeLines("incomplete table", area_catalog_path("N1000", cache))
  expect_identical(n_areas(1000, cache_dir = cache), first)
})

test_that("name and code reads share disk and memory cache including offline use", {
  cache <- tempfile("kartdata-area-read-")
  archive <- small_archive()
  on.exit(unlink(c(cache, archive), recursive = TRUE))
  local_mocked_bindings(feed_xml = function(url) if (identical(url, service_feed)) service_fixture() else area_fixture(),
    discover = function(sel) c(sel[c("series", "area", "epsg")], list(format = "GML", feed = service_feed,
      url = "https://nedlasting.geonorge.no/fixture.zip", updated = "v1")),
    http_get = function(url, path) file.copy(archive, path))
  first <- n_get("Veglenke", area = "Oslo", format = "GML", cache_dir = cache)
  expect_identical(n_cache_info(cache_dir = cache)$area, "03")
  local_mocked_bindings(feed_xml = function(...) stop("offline"), http_get = function(...) stop("unexpected download"))
  expect_identical(n_get("Veglenke", area = 3, format = "GML", cache_dir = cache), first)
  expect_identical(n_get("Veglenke", area = " oslo ", format = "GML", cache_dir = cache), first)
  expect_error(n_get("Veglenke", area = "Oslo", format = "GML", refresh = "check", cache_dir = cache), "offline")
})
