# Publication-style figures for the concise pooled report.
# This restores the report's established ggplot2 + Heiti SC visual system.
suppressPackageStartupMessages(library(ggplot2))

args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2)
source_dir <- args[[1]]
figure_dir <- args[[2]]
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

font <- "Heiti SC"
blue <- "#245774"
ink <- "#111111"
muted <- "#555555"

save_figure <- function(plot, stem, width, height) {
  ggsave(
    file.path(figure_dir, paste0(stem, ".png")), plot,
    width = width, height = height, dpi = 320,
    device = ragg::agg_png, bg = "white"
  )
  grDevices::quartz(
    type = "pdf", file = file.path(figure_dir, paste0(stem, ".pdf")),
    width = width, height = height, family = font
  )
  print(plot)
  grDevices::dev.off()
}

# Sample flow: sequential exclusions are kept distinct.
flow <- read.csv(file.path(source_dir, "review", "sample_flow.csv"),
                 stringsAsFactors = FALSE, check.names = FALSE)
steps <- c("All_DEMO", "age_20_79", "valid_MEC_design", "known_ever_asthma",
           "RA_or_explicit_no_arthritis", "smoking")
labels <- c("全部人口学记录", "年龄20至79岁", "体检抽样设计有效",
            "曾患哮喘状态明确", "疾病状态符合比较要求", "最终完整病例")
reasons <- c("年龄不符合", "权重或抽样设计无效", "哮喘状态不明",
             "其他关节炎或关节炎状态不明", "协变量不完整")
remaining <- setNames(flow$remaining, flow$step)[steps]
nodes <- data.frame(
  x = 3.0, y = 6:1,
  label = paste0(labels, "  ", format(remaining, big.mark = ","), "人"),
  final = c(rep(FALSE, 5), TRUE)
)
exclusions <- data.frame(
  x = 6.25, y = 5.53:1.53,
  label = paste0(reasons, "\n排除 ",
                 format(remaining[-length(remaining)] - remaining[-1], big.mark = ","), "人")
)
flow_plot <- ggplot() +
  geom_rect(
    data = nodes,
    aes(xmin = x - 2.35, xmax = x + 2.35, ymin = y - .34, ymax = y + .34,
        fill = final),
    color = "#B8C9D2", linewidth = .45, show.legend = FALSE
  ) +
  scale_fill_manual(values = c("FALSE" = "#FAFBFC", "TRUE" = "#EEF4F7")) +
  geom_text(data = nodes, aes(x, y, label = label), family = font, size = 3.2,
            color = ink) +
  geom_segment(
    data = data.frame(y = 5.66:1.66),
    aes(x = 3.0, xend = 3.0, y = y, yend = y - .32),
    color = blue, linewidth = .45,
    arrow = grid::arrow(length = grid::unit(.09, "inches"))
  ) +
  geom_segment(
    data = exclusions,
    aes(x = 5.35, xend = 5.88, y = y, yend = y),
    color = blue, linewidth = .4
  ) +
  geom_text(data = exclusions, aes(x, y, label = label), hjust = 0,
            family = font, size = 2.85, lineheight = 1.08, color = muted) +
  coord_cartesian(xlim = c(.4, 9.55), ylim = c(.55, 6.45), clip = "off") +
  theme_void(base_family = font) +
  theme(plot.margin = margin(4, 4, 4, 4))
save_figure(flow_plot, "sample_flow", 6.73, 3.40)

# Main models: replace the dense regression table with a publication-style forest plot.
models <- read.csv(file.path(source_dir, "regression.csv"),
                   stringsAsFactors = FALSE, check.names = FALSE)
models$display <- c("模型0  未调整", "模型1  年龄、性别、种族或族裔",
                    "模型2  再加教育、贫困收入比", "模型3  再加体质指数、吸烟")
models$y <- 4:1
models$value <- sprintf("%.2f（%.2f—%.2f）", models$OR, models$lower, models$upper)
models$p_display <- ifelse(models$p < .001, "<0.001", sprintf("%.3f", models$p))
model_plot <- ggplot(models, aes(OR, y)) +
  geom_vline(xintercept = 1, linetype = 2, color = "#858585", linewidth = .5) +
  geom_segment(aes(x = lower, xend = upper, yend = y), color = blue, linewidth = .65) +
  geom_point(shape = 15, size = 2.8, color = blue) +
  geom_text(aes(x = .34, label = display), family = font, hjust = 0,
            size = 2.95, color = ink) +
  geom_text(aes(x = 7.2, label = value), family = font, hjust = 1,
            size = 2.95, color = ink) +
  geom_text(aes(x = 8.8, label = p_display), family = font, hjust = 1,
            size = 2.95, color = ink) +
  annotate("text", x = .34, y = 4.75, label = "模型及调整因素", family = font,
           hjust = 0, size = 3.1, fontface = "bold") +
  annotate("text", x = 7.2, y = 4.75, label = "比值比（95%置信区间）", family = font,
           hjust = 1, size = 3.1, fontface = "bold") +
  annotate("text", x = 8.8, y = 4.75, label = "P值", family = font,
           hjust = 1, size = 3.1, fontface = "bold") +
  scale_x_log10(limits = c(.33, 9.2), breaks = c(1, 1.5, 2, 3, 4),
                labels = c("1", "1.5", "2", "3", "4")) +
  scale_y_continuous(limits = c(.45, 5.0), breaks = NULL) +
  labs(x = NULL, y = NULL) +
  theme_minimal(base_family = font, base_size = 10.5) +
  theme(panel.grid = element_blank(), axis.text.x = element_text(size = 9, color = muted),
        axis.ticks.x = element_line(color = "#999999"),
        axis.line.x = element_line(color = "#999999", linewidth = .35),
        plot.margin = margin(4, 4, 2, 4))
save_figure(model_plot, "model_forest", 6.73, 2.35)

# Age and sex are deliberately drawn as separate figures.
subgroups <- read.csv(file.path(source_dir, "subgroups.csv"),
                      stringsAsFactors = FALSE, check.names = FALSE)

subgroup_plot <- function(data, labels, stem, height) {
  data$display <- labels
  data$y <- rev(seq_len(nrow(data)))
  data$value <- sprintf("%.2f（%.2f—%.2f）", data$OR, data$lower, data$upper)
  header_y <- max(data$y) + .68
  plot <- ggplot(data, aes(OR, y)) +
    geom_vline(xintercept = 1, linetype = 2, color = "#858585", linewidth = .5) +
    geom_segment(aes(x = lower, xend = upper, yend = y), color = blue, linewidth = .65) +
    geom_point(shape = 15, size = 2.8, color = blue) +
    geom_text(aes(x = .34, label = display), family = font, hjust = 0,
              size = 3.0, color = ink) +
    geom_text(aes(x = .70, label = format(n, big.mark = ",", trim = TRUE)),
              family = font, hjust = 1, size = 3.0, color = ink) +
    geom_text(aes(x = 8.6, label = value), family = font, hjust = 1,
              size = 3.0, color = ink) +
    annotate("text", x = .34, y = header_y, label = "亚组", family = font,
             hjust = 0, size = 3.1, fontface = "bold") +
    annotate("text", x = .70, y = header_y, label = "实际人数", family = font,
             hjust = 1, size = 3.1, fontface = "bold") +
    annotate("text", x = 8.6, y = header_y, label = "比值比（95%置信区间）",
             family = font, hjust = 1, size = 3.1, fontface = "bold") +
    scale_x_log10(limits = c(.33, 9), breaks = c(1, 1.5, 2, 3, 4),
                  labels = c("1", "1.5", "2", "3", "4")) +
    scale_y_continuous(limits = c(.45, header_y + .2), breaks = NULL) +
    labs(x = NULL, y = NULL) +
    theme_minimal(base_family = font, base_size = 10.5) +
    theme(panel.grid = element_blank(), axis.text.x = element_text(size = 9, color = muted),
          axis.ticks.x = element_line(color = "#999999"),
          axis.line.x = element_line(color = "#999999", linewidth = .35),
          plot.margin = margin(4, 4, 2, 4))
  save_figure(plot, stem, 6.73, height)
}

subgroup_plot(subgroups[subgroups$subgroup_variable == "agegroup", ],
              c("20至39岁", "40至59岁", "60至79岁"), "age_forest", 1.90)
subgroup_plot(subgroups[subgroups$subgroup_variable == "sex", ],
              c("男性", "女性"), "sex_forest", 1.55)

cat("PASS: model, age and sex figures generated separately with ggplot2 and Heiti SC\n")
