res <- br(
  benefit("CV", function(x) x, weight = 0.25),
  risk("DVT", function(x) 1.3 * x, weight = 0.75),
  br_group(
    label = "PBO",
    CV = 10:20,
    DVT = 30:40
  ),
  br_group(
    label = "TRT",
    CV = 50:60,
    DVT = 70:80
  )
)

test_that("summary()", {
  exp_summary <- res %>%
    dplyr::group_by(label) %>%
    dplyr::summarize(
      mean = mean(total),
      `2.50%` = stats::quantile(total, .025, names = FALSE),
      `97.50%` = stats::quantile(total, .975, names = FALSE)
    ) %>%
    dplyr::ungroup()
  expect_equal(summary(res), list(summary = exp_summary, scores = res))
  # summary with null probs
  exp_summary2 <- dplyr::select(exp_summary, "label", "mean")
  expect_equal(
    summary(res, probs = NULL),
    list(summary = exp_summary2, scores = res)
  )
  # with adjustment
  trt <- dplyr::filter(res, .data$label == "TRT") %>% dplyr::pull(.data$total)
  exp_scores_adj <- res %>%
    dplyr::filter(.data$label != "TRT") %>%
    dplyr::mutate(
      total = .data$total - !!trt,
      reference = "TRT"
    )
  exp_summary_adj <- exp_scores_adj %>%
    dplyr::group_by(label) %>%
    dplyr::summarize(
      mean = mean(total),
      `2.50%` = stats::quantile(total, .025, names = FALSE),
      `97.50%` = stats::quantile(total, .975, names = FALSE),
      reference = "TRT"
    ) %>%
    dplyr::ungroup()

  expect_equal(
    summary(res, reference = "TRT"),
    list(summary = exp_summary_adj, scores = exp_scores_adj)
  )
})

test_that("pbrisk() and qbrisk()", {
  res <- br(
    benefit("CV", function(x) x, weight = 0.25),
    risk("DVT", function(x) 1.3 * x, weight = 0.75),
    br_group(
      label = "PBO",
      CV = rnorm(1e4),
      DVT = rnorm(1e4)
    ),
    br_group(
      label = "TRT",
      CV = rnorm(1e4),
      DVT = rnorm(1e4)
    )
  )
  out_q <- qbrisk(res, c(.025, .975))
  out_p <- pbrisk(res, out_q$quantile, direction = "lower")
  dplyr::left_join(out_q, out_p, by = c("label", quantile = "q")) %>%
    dplyr::mutate(equal = p == prob) %>%
    dplyr::pull(.data$equal) %>%
    all() %>%
    expect_true()

  # with adjustment
  out_q <- qbrisk(res, c(.025, .975), reference = "PBO")
  out_p <- pbrisk(res, out_q$quantile, reference = "PBO", direction = "lower")
  dplyr::left_join(out_q, out_p, by = c("label", quantile = "q")) %>%
    dplyr::mutate(equal = p == prob) %>%
    dplyr::pull(.data$equal) %>%
    all() %>%
    expect_true()

  # check direction argument
  out_p_upper <- pbrisk(
    res,
    out_q$quantile,
    reference = "PBO",
    direction = "upper"
  )
  expect_equal(1 - out_p$prob, out_p_upper$prob)
})
