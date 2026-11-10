# Prediction helpers for the saved Phase 2 models (same logic as pd_02_models.R),
# sourced by the interpretation and grading scripts.
suppressMessages({ library(glmnet); library(ranger); library(xgboost) })
YS <- c("y1", "y2", "y3"); MODELS <- c("null", "glm", "enet", "rf", "xgb", "ens")

pred_one <- function(m, X, simple_vars) {
  o <- data.frame(null = rep(m$rate, nrow(X)))
  o$glm  <- as.numeric(predict(m$glm, data.frame(X[, simple_vars, drop = FALSE]), type = "response"))
  o$enet <- if (is.null(m$enet)) m$rate else as.numeric(predict(m$enet, X, s = "lambda.min", type = "response"))
  o$rf   <- predict(m$rf, as.data.frame(X), num.threads = 1)$predictions[, "1"]
  o$xgb  <- predict(m$xgb, X)
  o$ens  <- (o$enet + o$rf + o$xgb) / 3
  o
}
predict_all <- function(S, d) {
  X <- apply_prep(S$M$prep, d)
  pr <- lapply(YS, function(y) pred_one(S$M$fits[[y]], X, S$simple_vars))
  out <- list()
  for (m in MODELS) {
    p1 <- pr[[1]][[m]]; p2 <- pmax(pr[[2]][[m]], p1); p3 <- pmax(pr[[3]][[m]], p2)
    out[[paste0("p1_", m)]] <- p1; out[[paste0("p2_", m)]] <- p2; out[[paste0("p3_", m)]] <- p3
  }
  as.data.frame(out)
}
# chosen model's probability for one threshold k (1, 2, 3)
pred_chosen <- function(S, d, k = 3) predict_all(S, d)[[paste0("p", k, "_", S$chosen)]]
