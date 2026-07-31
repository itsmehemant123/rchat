test_that("run_r_code evaluates and captures output", {
  res <- .rchat_tool_exec("run_r_code", list(code = "x <- 6 * 7; x"))
  expect_true(res$success)
  expect_match(res$output, "42")
})

test_that("run_r_code captures errors", {
  res <- .rchat_tool_exec("run_r_code", list(code = "stop('boom')"))
  expect_false(res$success)
  expect_match(res$output, "boom")
})

test_that("write/read/list files round-trip", {
  tmp <- tempfile(fileext = ".txt")
  res <- .rchat_tool_exec("write_file", list(path = tmp, content = "a\nb"))
  expect_true(res$success)
  expect_equal(.rchat_tool_exec("read_file", list(path = tmp))$content, "a\nb")
  files <- .rchat_tool_exec("list_files", list(path = dirname(tmp)))$files
  expect_true(basename(tmp) %in% basename(files))
})

test_that("tools are defined", {
  expect_true(length(.rchat_tools()) >= 9)
})
