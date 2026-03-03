#' @rdname br
#' @param name a string indicating the name of the benefit or risk.
#' @param fun a utility function which maps a parameter value to a utility
#'   value.
#' @param weight the weight of the benefit/risk.
#' @export
benefit <- function(name, fun, weight) {
  assert_chr(name)
  assert_function(fun, name)
  assert_num(weight)
  out <- list(name = name, fun = fun, weight = weight)
  class(out) <- c("brisk_benefit", "brisk_br")
  return(out)
}

#' @rdname br
#' @export
risk <- function(name, fun, weight) {
  assert_chr(name)
  assert_function(fun, name)
  assert_num(weight)
  out <- list(name = name, fun = fun, weight = weight)
  class(out) <- c("brisk_risk", "brisk_br")
  return(out)
}

#' Bayesian Benefit Risk
#' @param ... calls to `benefit()`, `risk()`, and `br_group()` to define the
#'   utility functions and treatment groups.
#' @details The `br()` function allows the user to define an arbitrary number
#'   of "benefits" and "risks".  Each benefit/risk requires a utility
#'   function (`fun`) and a weight.  The utility function maps the benefit/risk
#'   parameter to a utility score.  The `br_group()` function supplies samples
#'   from the posterior distribution for each benefit risk for a specific
#'   group (e.g. treatment arm).
#'
#'   The `br()` function then calculates the posterior distribution of the
#'   overall utility for each group.  The overall utility is a weighted sum of
#'   the utilities for each benefit/risk.
#'
#'   The `mcda()` function is the same as `br()`, but has extra checks to
#'   ensure that the total weight of all benefits and risks is 1, and that the
#'   utility functions produce values between 0 and 1 for all posterior
#'   samples.
#' @return A named list with posterior summaries of utility for each group and
#'   the raw posterior utility scores.
#' @example man/examples/ex-mcda.R
#' @export
br <- function(...) {
  args <- list(...)
  brs <- get_brs(args)
  groups <- get_groups(args)
  assert_no_extra_args(args, brs, groups)
  assert_brs(brs)
  assert_groups(groups, brs)
  scores <- purrr::map_dfr(groups, get_group_utility, brs = brs)
  total <- rowSums(dplyr::select(scores, ends_with("_score")))
  scores <- scores %>%
    dplyr::mutate(total = !!total) %>%
    dplyr::as_tibble()
  class(scores) <- c("brisk_br", class(scores))
  return(scores)
}

#' @rdname br
#' @export
mcda <- function(...) {
  args <- list(...)
  brs <- get_brs(args)
  assert_weights(brs)
  scores <- br(...)
  assert_utility_range(scores)
  class(scores) <- c("brisk_mcda", class(scores))
  return(scores)
}

get_brs <- function(x) {
  ind <- vapply(x, inherits, logical(1), what = "brisk_br")
  x[ind]
}

get_groups <- function(x) {
  ind <- vapply(x, inherits, logical(1), what = "brisk_group")
  x[ind]
}

#' Posterior Samples for a Benefit/Risk Group
#' @param label a string indicating the name of the group.
#' @param ... named arguments which correspond to the names of the
#'   benefits/risks specified by `benefit()` and `risk()` in a call to `br()`.
#' @details This function is intended to be used as an input argument to
#'   the `br()` function.
#' @return A named list with the posterior samples and an assigned S3 class.
#' @example man/examples/ex-br.R
#' @export
br_group <- function(label, ...) {
  samps <- list(...)
  attr(samps, "label") <- label
  class(samps) <- "brisk_group"
  return(samps)
}

#' Summarize Bayesian Benefit-Risk Scores
#' @param object output from a call to `brisk::br()` or `brisk::mcda()`.
#' @param probs a vector of probabilities used to obtain quantiles of
#'   the posterior of the weighted utilities for each group.
#' @param reference a string indicating which group is the reference group which
#'   is used to subtract scores from other groups.
#' @param ... Additional arguments which throw an error if specified.
#' @return A named list with the posterior summary, and the scores from the
#'   `object` object (which are adjusted if `reference` is specified).
#' @example man/examples/ex-br.R
#' @export
summary.brisk_br <- function(
  object,
  probs = c(.025, .975),
  reference = NULL,
  ...
) {
  rlang::check_dots_empty()
  scores <- adjust_column(object, reference, "total")
  sumry <- scores %>%
    dplyr::group_by(.data$label) %>%
    dplyr::reframe(
      mean = mean(.data$total),
      qtiles = safe_quantile(.data$total, prob = !!probs),
      probs = probs
    )
  if (!is.null(probs)) {
    sumry <- sumry %>%
      dplyr::mutate(qtile_label = sprintf("%.2f%%", 100 * probs)) %>%
      dplyr::select(-"probs") %>%
      tidyr::pivot_wider(
        names_from = "qtile_label",
        values_from = "qtiles"
      ) %>%
      dplyr::ungroup()
  }
  sumry <- dplyr::mutate(sumry, reference = !!reference)
  list(summary = sumry, scores = scores)
}

#' @title Calculate Quantiles and Probabilities
#' @description Calculates posterior quantiles and probabilities on
#'   benefit-risk scores.
#' @inheritParams summary.brisk_br
#' @param x output from a call to `brisk::br()` or `brisk::mcda()`.
#' @param q vector of quantiles.
#' @param direction the direction of the posterior probability to compute.
#' @return A tibble with the quantile and posterior probability of the
#'   benefit-risk score for each group.
#' @example man/examples/ex-pbrisk.R
#' @export
pbrisk <- function(x, q, reference = NULL, direction = c("upper", "lower")) {
  direction <- match.arg(direction)
  scores <- summary(x, reference = reference, probs = NULL)$scores
  scores <- scores %>% dplyr::group_by(.data$label)
  out <- purrr::map_dfr(q, get_prob, x = scores) %>%
    dplyr::mutate(direction = !!direction, reference = !!reference) %>%
    dplyr::arrange(.data$label, .data$q)
  if (direction == "upper") {
    out <- dplyr::mutate(out, prob = 1 - .data$prob)
  }
  return(out)
}

#' @rdname pbrisk
#' @param p a vector of probabilities from which to compute posterior quantiles.
#' @export
qbrisk <- function(x, p, reference = NULL) {
  assert_p(p)
  scores <- summary(x, reference = reference, probs = NULL)$scores
  scores <- scores %>% dplyr::group_by(.data$label)
  out <- purrr::map_dfr(p, get_quantile, x = scores) %>%
    dplyr::arrange(.data$label, .data$p) %>%
    dplyr::mutate(reference = !!reference)
  return(out)
}

get_prob <- function(x, q) {
  x %>%
    dplyr::summarize(
      q = !!q,
      prob = mean(.data$total < !!q),
      .groups = "drop"
    )
}

get_quantile <- function(x, p) {
  x %>%
    dplyr::summarize(
      p = !!p,
      quantile = stats::quantile(.data$total, prob = p, names = FALSE),
      .groups = "drop"
    )
}



safe_quantile <- function(x, prob) {
  if (is.null(prob)) return(NULL)
  stats::quantile(x, prob = prob, names = FALSE)
}

adjust_column <- function(scores, reference, col) {
  col <- rlang::enquo(col)
  assert_reference(scores, reference)
  if (is.null(reference)) return(scores)
  scores_ref <- dplyr::filter(scores, .data$label == !!reference)
  scores <- dplyr::filter(scores, .data$label != !!reference)
  scores <- scores %>%
    dplyr::left_join(scores_ref, by = "iter", suffix = c("", "_ref")) %>%
    dplyr::mutate(
      across(
        !!col,
        ~ .x - dplyr::pick(paste0(cur_column(), "_ref"))[[1]]
      )
    ) %>%
    dplyr::select(- ends_with("_ref")) %>%
    dplyr::mutate(reference = !!reference)
}

get_weight_length <- function(x) {
  length(x$weight)
}

get_group_utility <- function(br_group, brs) {
  purrr::map_dfc(brs, get_utility, br_group = br_group) %>%
    dplyr::mutate(
      label = attr(br_group, "label"),
      iter = seq_len(n())
    )
}

get_utility <- function(x, br_group) {
  samples <- br_group[[x$name]]
  out <- data.frame(
    samps = samples,
    weight = x$weight,
    utility =  x$f(samples)
  ) %>%
    dplyr::mutate(score = .data$weight * .data$utility)
  colnames(out) <- c(x$name, paste0(x$name, c("_weight", "_utility", "_score")))
  out
}
