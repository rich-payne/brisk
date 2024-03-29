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
#'   of "benefits" and "risks".  Each benefit/risk takes requires a utility
#'   function (`fun`) and a weight.  The utility function maps the benefit/risk
#'   parameter to a utility scores.  The `br_group()` function supplies samples
#'   from the posterior distribution for each benefit risk for a specific
#'   group (e.g. treatment arm).
#'
#'   The `br()` function then calculates the posterior distribution of the
#'   overall utility for each group.  The overall utility is a weighted sum of
#'   the utilities for each benefit/risk.
#' @return A named list with posterior summaries of utility for each group and
#'   the raw posterior utility scores.
#' @example man/examples/ex-br.R
#' @export
br <- function(...) {
  args <- list(...)
  brs <- get_brs(args)
  groups <- get_groups(args)
  assert_brs(brs)
  assert_groups(groups, brs)
  scores <- purrr::map_dfr(groups, get_group_utility, brs = brs) %>%
    dplyr::rowwise() %>%
    dplyr::mutate(total = sum(c_across(ends_with("_utility")))) %>%
    dplyr::ungroup()
  sumry <- scores %>%
    dplyr::group_by(.data$label) %>%
    dplyr::summarize(
      mean = mean(.data$total),
      lb = stats::quantile(.data$total, prob = .025),
      ub = stats::quantile(.data$total, prob = .975),
    )
  out <- list(summary = sumry, scores = scores)
  w <- purrr::map(brs, get_weight)
  w <- do.call("c", w)
  attr(out, "weights") <- w
  return(out)
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

get_weight <- function(x) {
  out <- x$weight
  names(out) <- x$name
  out
}

get_group_utility <- function(br_group, brs) {
  purrr::map_dfc(brs, get_utility, br_group = br_group) %>%
    dplyr::mutate(
      label = attr(br_group, "label"),
      iter = 1:n()
    )
}

get_utility <- function(x, br_group) UseMethod("get_utility")

#' @export
get_utility.brisk_benefit <- function(x, br_group) {
  samples <- br_group[[x$name]]
  out <- data.frame(
    y = samples,
    x = x$weight * x$f(samples)
  )
  colnames(out) <- c(x$name, paste0(x$name, "_utility"))
  out
}

#' @export
get_utility.brisk_risk <- function(x, br_group) {
  samples <- br_group[[x$name]]
  out <- data.frame(
    y = samples,
    x = - x$weight * x$f(samples)
  )
  colnames(out) <- c(x$name, paste0(x$name, "_utility"))
  out
}
