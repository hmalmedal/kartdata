test_that("progress defaults to interactivity and respects explicit settings", {
  old <- options(kartdata.progress = NULL)
  on.exit(options(old), add = TRUE)
  expect_identical(progress_enabled(), interactive())
  options(kartdata.progress = TRUE)
  expect_message(progress_message("Working"), "Working")
  options(kartdata.progress = FALSE)
  expect_silent(progress_message("Working"))
  expect_silent({
    counter <- progress_counter(2, "Working")
    counter$update(1)
    counter$close()
  })
  options(kartdata.progress = NA)
  expect_error(progress_enabled(), "must be TRUE or FALSE")
})

test_that("download progress is enabled only for file transfers when requested", {
  old <- options(kartdata.progress = TRUE)
  on.exit(options(old), add = TRUE)
  requests <- list()
  local_mocked_bindings(req_perform = function(req, path = NULL) {
    requests[[length(requests) + 1L]] <<- req
    httr2::response(200)
  }, .package = "httr2")
  http_get(service_feed)
  http_get("https://nedlasting.geonorge.no/a.zip", path = tempfile())
  options(kartdata.progress = FALSE)
  http_get("https://nedlasting.geonorge.no/a.zip", path = tempfile())
  expect_null(requests[[1]]$options$xferinfofunction)
  expect_type(requests[[2]]$options$xferinfofunction, "closure")
  expect_identical(requests[[2]]$options$noprogress, FALSE)
  expect_null(requests[[3]]$options$xferinfofunction)
})

test_that("object type progress counts completed layers and closes on error", {
  closed <- 0L
  updates <- integer()
  local_mocked_bindings(
    source_layers = function(...) data.frame(layer = c("one", "two"), source = "fixture.gdb"),
    progress_counter = function(total, label) {
      expect_equal(total, 2)
      list(update = function(i) { updates <<- c(updates, i) },
           close = function() { closed <<- closed + 1L })
    })
  local_mocked_bindings(st_read = function(...) data.frame(objtype = "Veglenke"), .package = "sf")
  layer_index("unused", "FGDB")
  expect_identical(updates, 1:2)
  expect_equal(closed, 1)
  updates <- integer()
  local_mocked_bindings(st_read = function(...) stop("read failed"), .package = "sf")
  expect_error(layer_index("unused", "FGDB"), "read failed")
  expect_length(updates, 0)
  expect_equal(closed, 2)
})

test_that("read progress describes actual work, while memory cache hits stay silent", {
  old <- options(kartdata.progress = TRUE)
  on.exit(options(old), add = TRUE)
  state <- new.env(parent = emptyenv())
  state$entries <- list()
  archive <- small_archive()
  cache <- tempfile("kartdata-progress-")
  on.exit(unlink(c(cache, archive), recursive = TRUE), add = TRUE)
  local_mocked_bindings(.read_cache = state,
    discover = function(sel) c(sel[c("series", "area", "epsg")], list(format = "GML", feed = service_feed,
      url = "https://nedlasting.geonorge.no/fixture.zip", updated = "v1")),
    http_get = function(url, path) file.copy(archive, path))
  messages <- character()
  first <- withCallingHandlers(n_get("Veglenke", format = "GML", cache_dir = cache),
    message = function(m) { messages <<- c(messages, conditionMessage(m)); invokeRestart("muffleMessage") })
  expect_true(any(grepl("Downloading", messages)))
  expect_true(any(grepl("Unpacking", messages)))
  expect_true(any(grepl("Reading layer 'Veglenke'", messages)))
  expect_true(any(grepl("Read 2 features", messages)))
  expect_silent(second <- n_get("Veglenke", format = "GML", cache_dir = cache))
  expect_identical(first, second)
  options(kartdata.progress = FALSE)
  expect_silent(n_get("Veglenke", format = "GML", cache_dir = cache, refresh = "force"))
  expect_error(n_get("missing", format = "GML", cache_dir = cache), "Unknown layer")
})
