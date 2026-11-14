# Local static server for browser checks (dev only): Rscript tools/serve_local.R <port>
# Serves the site worktree at / and the dev folder at /dev/ (dv_15_expected.js, dv_15_check.js). Binds to 127.0.0.1 only.
a <- commandArgs(trailingOnly = TRUE); port <- if (length(a)) as.integer(a[1]) else 8765
roots <- c(dev = normalizePath("."), site = normalizePath("../ProspectActuary_wt"))
types <- c(html = "text/html; charset=utf-8", js = "application/javascript", css = "text/css", csv = "text/csv", json = "application/json", png = "image/png", svg = "image/svg+xml")
app <- list(call = function(req) {
  p <- utils::URLdecode(req$PATH_INFO); if (grepl("..", p, fixed = TRUE)) return(list(status = 403L, headers = list(), body = "no"))
  root <- if (startsWith(p, "/dev/")) roots["dev"] else roots["site"]; if (startsWith(p, "/dev/")) p <- sub("^/dev", "", p)
  f <- file.path(root, p); if (dir.exists(f)) f <- file.path(f, "index.html")
  if (!file.exists(f)) return(list(status = 404L, headers = list("Content-Type" = "text/plain"), body = "not found"))
  ext <- tolower(tools::file_ext(f)); ct <- if (ext %in% names(types)) types[[ext]] else "application/octet-stream"
  list(status = 200L, headers = list("Content-Type" = ct, "Cache-Control" = "no-store"), body = readBin(f, "raw", file.size(f))) })
s <- httpuv::startServer("127.0.0.1", port, app); cat("serving on http://127.0.0.1:", port, "\n", sep = "")
while (TRUE) httpuv::service(100)
