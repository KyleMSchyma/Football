# Diagnostics on each design: strongest correlations, VIF, curvature test (GAM smooth vs linear, in-sample),
# and Friedman's H-statistic for pairwise interactions from a probability random forest on the any-tier hit.
suppressMessages({ library(dplyr); library(mgcv); library(ranger) })
args <- commandArgs(trailingOnly = TRUE); FILES <- if (length(args)) args else Sys.glob("*_design.rds")
Hstat <- function(rf, X, vars, n = 150) { set.seed(2026); S <- X[sample.int(nrow(X), min(n, nrow(X))), , drop = FALSE]
  pd <- function(cols) { sapply(seq_len(nrow(S)), function(i) { Z <- S; for (c in cols) Z[, c] <- S[i, c]; mean(predict(rf, as.data.frame(Z), num.threads = 4)$predictions[, "1"]) }) }
  one <- lapply(setNames(vars, vars), function(v) { x <- pd(v); x - mean(x) })
  prs <- t(combn(vars, 2))
  bind_rows(lapply(seq_len(nrow(prs)), function(r) { a <- prs[r, 1]; b <- prs[r, 2]; j <- pd(c(a, b)); j <- j - mean(j)
    data.frame(var1 = a, var2 = b, H = sqrt(sum((j - one[[a]] - one[[b]])^2) / sum(j^2))) })) }
out_cor <- list(); out_vif <- list(); out_gam <- list(); out_h <- list()
for (f in FILES) { nm <- sub("_design.rds", "", f); L <- readRDS(f); X <- L$X; D <- L$D; cont <- L$cont
  Xc <- X[, cont, drop = FALSE]; Xc <- Xc[, apply(Xc, 2, sd) > 0, drop = FALSE]; cont <- colnames(Xc)
  C <- cor(Xc); ut <- which(upper.tri(C), arr.ind = TRUE)
  cc <- data.frame(design = nm, var1 = rownames(C)[ut[, 1]], var2 = colnames(C)[ut[, 2]], r = C[ut]) %>% arrange(desc(abs(r)))
  out_cor[[nm]] <- head(cc, 12)
  vif <- diag(MASS::ginv(cor(Xc))); names(vif) <- colnames(Xc)   # continuous inputs only (missing flags duplicate some binary flags exactly)
  out_vif[[nm]] <- data.frame(design = nm, var = names(vif), VIF = vif) %>% arrange(desc(VIF))
  # curvature: logistic GAM on any-tier with each continuous input smooth vs linear, others linear
  y <- D$y3; df <- data.frame(Xc, y = y, check.names = FALSE); names(df) <- make.names(names(df))
  lin <- glm(y ~ ., family = binomial, data = df)
  for (v in make.names(cont)) { if (length(unique(df[[v]])) < 8) next
    fo <- as.formula(paste("y ~", paste(setdiff(make.names(cont), v), collapse = " + "), "+ s(", v, ", k = 5)"))
    g <- tryCatch(gam(fo, family = binomial, data = df, method = "REML"), error = function(e) NULL); if (is.null(g)) next
    st <- summary(g)$s.table
    out_gam[[length(out_gam) + 1]] <- data.frame(design = nm, var = v, edf = st[1, "edf"], p_smooth = st[1, "p-value"], dAIC_vs_linear = AIC(g) - AIC(lin)) }
  # H-statistic among the top 6 inputs by permutation importance
  rf <- ranger(x = as.data.frame(X), y = factor(y, levels = 0:1), probability = TRUE, num.trees = 500, min.node.size = 20, importance = "permutation", seed = 2026, num.threads = 4)
  top <- names(sort(rf$variable.importance, decreasing = TRUE))[1:6]
  out_h[[nm]] <- Hstat(rf, X, top) %>% mutate(design = nm, .before = 1) %>% arrange(desc(H))
  cat(nm, "done\n") }
write.csv(bind_rows(out_cor), "diag_top_correlations.csv", row.names = FALSE)
write.csv(bind_rows(out_vif), "diag_vif.csv", row.names = FALSE)
write.csv(bind_rows(out_gam), "diag_curvature_gam.csv", row.names = FALSE)
write.csv(bind_rows(out_h), "diag_hstat.csv", row.names = FALSE)
