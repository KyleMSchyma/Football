# Value-level backtest of the still-playing add-on terms (dev only; the live dv_11 file is not changed).
# Run from a COPY of the Football2_Dynasty folder:  Rscript run_actx.R 0   (live)   and   Rscript run_actx.R 1   (with terms)
# Each run writes exp/dv11_live.rds or exp/dv11_actx.rds (NO_WRITE: no board or backtest CSVs are touched); then Rscript cmp_actx.R.
a <- commandArgs(trailingOnly = TRUE); ACT_X <- a[1] == "1"; NO_WRITE <- TRUE; EXP_TAG <- if (ACT_X) "actx" else "live"
src <- paste(readLines("dv_11_dynasty_v4.R"), collapse = "\n")
XT <- " + I(cppg^2) + cppg:age + lpick:factor(pmin(exp, 3))"
if (ACT_X) {
  old1 <- "act  <- glm(played_next ~ cppg + age_ns(age) + factor(pmin(exp, 3)) + lpick, data = x"
  old2 <- "played_next ~ cppg + age_ns(age) + factor(pmin(exp, 3)) + lpick + depthf + ss else"
  old3 <- "played_next ~ cppg + age_ns(age) + factor(pmin(exp, 3)) + lpick + depthf, data = x"
  stopifnot(grepl(old1, src, fixed = TRUE), grepl(old2, src, fixed = TRUE), grepl(old3, src, fixed = TRUE))
  src <- sub(old1, paste0("act  <- glm(played_next ~ cppg + age_ns(age) + factor(pmin(exp, 3)) + lpick", XT, ", data = x"), src, fixed = TRUE)
  src <- sub(old2, paste0("played_next ~ cppg + age_ns(age) + factor(pmin(exp, 3)) + lpick + depthf + ss", XT, " else"), src, fixed = TRUE)
  src <- sub(old3, paste0("played_next ~ cppg + age_ns(age) + factor(pmin(exp, 3)) + lpick + depthf", XT, ", data = x"), src, fixed = TRUE)
}
eval(parse(text = src))
