test_that("GML cache reuses offline, updates transactionally and clears selectively", {
  archive <- small_archive()
  cache <- tempfile("kartdata-cache-")
  on.exit(unlink(c(cache, archive), recursive = TRUE))
  downloads <- 0L
  version <- "2026-09-26T23:52:40"
  local_mocked_bindings(
    discover = function(sel) c(sel[c("series", "area", "epsg")], list(format = "GML", feed = service_feed,
      url = "https://nedlasting.geonorge.no/fixture.zip", updated = version)),
    http_get = function(url, path = NULL) { downloads <<- downloads + 1L; file.copy(archive, path); invisible(NULL) })
  expect_true("Veglenke" %in% n_layers(cache_dir = cache, format = "GML"))
  expect_s3_class(n_get("Veglenke", cache_dir = cache, format = "GML"), "sf")
  expect_equal(downloads, 1L)
  n_layers(cache_dir = cache, format = "GML", refresh = "check")
  expect_equal(downloads, 1L)
  expect_false(n_cache_info(cache_dir = cache, check = TRUE)$update_available)
  version <- "2026-09-28T00:00:00"
  expect_true(n_cache_info(cache_dir = cache, check = TRUE)$update_available)
  n_layers(cache_dir = cache, format = "GML", refresh = "check")
  expect_equal(downloads, 2L)
  n_layers(cache_dir = cache, format = "GML", refresh = "force")
  expect_equal(downloads, 3L)
  expect_true(n_cache_info(cache_dir = cache, verify = TRUE)$valid)
  local_mocked_bindings(discover = function(...) stop("offline"), http_get = function(...) stop("offline"))
  expect_s3_class(n_get("Veglenke", cache_dir = cache, format = "GML"), "sf")
  expect_error(n_get("no-such-layer", cache_dir = cache, format = "GML"), "Available layers.*Veglenke")
  expect_error(n_layers(cache_dir = cache, format = "GML", refresh = "force"), "offline")
  expect_true(n_cache_info(cache_dir = cache)$valid)
  unrelated <- file.path(cache, "keep.txt")
  writeLines("keep", unrelated)
  expect_length(n_cache_clear("N50", cache), 0)
  expect_length(n_cache_clear("N1000", cache), 1)
  expect_true(file.exists(unrelated))
  expect_equal(nrow(n_cache_info(cache_dir = cache)), 0)
})

test_that("corrupt downloads never replace good cache; incomplete cache is reported", {
  archive <- small_archive()
  cache <- tempfile("kartdata-cache-")
  on.exit(unlink(c(cache, archive), recursive = TRUE))
  local_mocked_bindings(discover = function(sel) c(sel[c("series", "area", "epsg")],
    list(format = "GML", feed = service_feed, url = "https://nedlasting.geonorge.no/fixture.zip", updated = "v1")),
    http_get = function(url, path) file.copy(archive, path))
  n_layers(cache_dir = cache, format = "GML")
  local_mocked_bindings(http_get = function(url, path) writeLines("broken", path))
  expect_error(n_layers(cache_dir = cache, format = "GML", refresh = "force"), "ZIP")
  expect_true(n_cache_info(cache_dir = cache)$valid)
  path <- n_cache_info(cache_dir = cache)$path
  writeLines("broken", file.path(path, "original.zip"))
  expect_false(n_cache_info(cache_dir = cache)$valid)
  expect_error(n_layers(cache_dir = cache, format = "GML"), "Corrupt or incomplete cache")
  expect_true(all(!safe_members(c("../bad", "C:/bad", "/bad", "a/../../bad", "..\\bad"))))
})

test_that("FGDB object types use selective SQL and preserve original attributes", {
  skip_if_not("OpenFileGDB" %in% sf::st_drivers()$name)
  archive <- small_archive("FGDB")
  cache <- tempfile("kartdata-cache-")
  on.exit(unlink(c(cache, archive), recursive = TRUE))
  local_mocked_bindings(discover = function(sel) c(sel[c("series", "area", "epsg")],
    list(format = "FGDB", feed = service_feed, url = "https://nedlasting.geonorge.no/fixture.zip", updated = "v1")),
    http_get = function(url, path) file.copy(archive, path))
  expect_true(all(c("Veglenke", "Bane") %in% n_layers(cache_dir = cache)))
  veg <- n_get("Veglenke", cache_dir = cache)
  expect_equal(nrow(veg), 1)
  expect_equal(veg$objtype, "Veglenke")
  expect_equal(veg$kommunenummer, "0301")
  expect_equal(sf::st_crs(veg)$epsg, 25833)
  expect_equal(nrow(n_get("N1000_Samferdsel_senterlinje", cache_dir = cache)), 2)
})
