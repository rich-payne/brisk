#' Plot Benefit/Risk Posterior Scores
#' @param x output from a call to `br()` or `mcda()`.
#' @param ... additional arguments throw an error.
#' @inheritParams summary.brisk_br
#' @return A ggplot object plotting the posterior densities of the weighted
#'   utility scores.
#' @example man/examples/ex-mcda.R
#' @family plots
#' @export
plot.brisk_br <- function(x, reference = NULL, ...) {
  rlang::check_dots_empty()
  scores <- summary(x, reference = reference)$scores
  title <- adjust_title("Benefit-Risk Score Distribution", reference)
  p <- ggplot(
    scores,
    aes(
      .data$total,
      group = .data$label,
      fill = .data$label,
      color = .data$label
    )
  ) +
    geom_density(alpha = 0.5) +
    labs(
      x = "Benefit-Risk Score",
      y = "Density",
      fill = "Label",
      color = "Label"
    ) +
    ggtitle(title) +
    theme(plot.title = element_text(hjust = 0.5))
  return(p)
}

#' Plot Posterior Mean Utility Scores
#' @inheritParams plot.brisk_br
#' @param stacked logical indicating if a stacked version of the barplot should
#'   be produced.
#' @return A ggplot barplot of the posterior mean weighted utility scores.
#' @family plots
#' @example man/examples/ex-mcda.R
#' @export
plot_utility <- function(x, reference = NULL, stacked = FALSE) {
  scores <- adjust_column(x, reference, ends_with("_score"))
  post_mean <- scores %>%
    dplyr::group_by(across(all_of("label"))) %>%
    dplyr::summarize(
      across(ends_with("_score"), mean),
      .groups = "drop"
    ) %>%
    tidyr::pivot_longer(
      -"label",
      names_to = "Outcome",
      values_to = "Score"
    ) %>%
    dplyr::mutate(Outcome = sub("_score$", "", .data$Outcome))
  title <- adjust_title("Posterior Mean Weighted Utility", reference)
  if (!stacked)  {
    p <- ggplot(post_mean, aes(.data$Score, .data$Outcome)) +
      geom_bar(stat = "identity") +
      facet_wrap(~ .data$label) +
      ggtitle(title) +
      theme(plot.title = element_text(hjust = 0.5))
  } else {
    data_label <- post_mean %>%
      dplyr::group_by(across(all_of("label"))) %>%
      dplyr::summarise(Score = sum(.data$Score))
    p <- ggplot(
      post_mean,
      aes(
        .data$label,
        .data$Score,
        color = .data$Outcome,
        fill = .data$Outcome
      )
    ) +
      geom_bar(stat = "identity") +
      ggtitle(title) +
      theme(plot.title = element_text(hjust = 0.5)) +
      geom_text(
        aes(
          label = round(.data$Score, 2),
          color = NULL,
          fill = NULL,
          vjust = - .25
        ),
        data = data_label
      )
  }
  return(p)
}

adjust_title <- function(title, reference) {
  if (is.null(reference)) return(title)
  title <- paste0(title, "\n", "(Adjusted Relative to ", reference, ")")
}
