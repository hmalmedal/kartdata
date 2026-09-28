test_that("series and selectors are validated before any network call", {
  expect_identical(series_name(1000), "N1000")
  expect_identical(series_name("n50"), "N50")
  expect_equal(nrow(n_products()), 7)
  expect_error(n_layers("N123"), "Unknown N-series")
  expect_error(selection("N1000", "../", 25833, "auto"), "area")
  expect_error(selection("N1000", "0000", NA, "auto"), "epsg")
})

test_that("feeds are matched by metadata ID and format, not incorrect MIME types", {
  feeds <- product_feeds(service_fixture(), "N1000")
  expect_identical(feeds$format, c("FGDB", "GML"))
  expect_true(all(startsWith(feeds$feed, "https://")))
  entry <- download_entry(file_fixture(), "0000", 25833)
  expect_match(entry$url, "FGDB.zip", fixed = TRUE)
  expect_null(download_entry(file_fixture(), "03", 25833))
  expect_null(download_entry(file_fixture(), "0000", 25832))
  expect_error(product_feeds(service_fixture(), "N50"), "No FGDB/GML")
  expect_error(download_entry(file_fixture(""), "0000", 25833), "updated")
  expect_error(entries(xml2::read_xml("<html/>")), "not an ATOM")
  expect_error(official_url("https://example.com/a.zip"), "Unexpected")
})

test_that("auto chooses FGDB and falls back to GML for availability and drivers", {
  mock_discovery()
  sel <- selection(1000, "0000", 25833, "auto")
  expect_identical(discover(sel)$format, "FGDB")
  local_mocked_bindings(readable_formats = function() "GML")
  expect_identical(discover(sel)$format, "GML")
  expect_error(discover(selection(1000, "0000", 25833, "FGDB")), "Local GDAL")
  local_mocked_bindings(readable_formats = function() c("FGDB", "GML"),
                        feed_xml = function(url) if (identical(url, service_feed)) service_fixture("GML") else file_fixture())
  expect_identical(discover(sel)$format, "GML")
})

test_that("HTTP errors and malformed responses are informative", {
  httr2::local_mocked_responses(list(httr2::response(404)))
  expect_error(http_get(service_feed), "Could not retrieve data from Geonorge")
})

test_that("real HTTP response decoding handles ATOM and malformed XML", {
  response <- httr2::response(200, headers = list(`content-type` = "application/atom+xml"),
                              body = charToRaw(as.character(service_fixture())))
  httr2::local_mocked_responses(list(response))
  expect_equal(nrow(product_feeds(feed_xml(service_feed), "N1000")), 2)
  httr2::local_mocked_responses(list(httr2::response(200, body = charToRaw("not xml"))))
  expect_error(feed_xml(service_feed), "Invalid Geonorge ATOM")
})
