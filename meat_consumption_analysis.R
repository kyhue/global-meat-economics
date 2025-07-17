# Load libraries
library(tidyverse)
library(glmnet)
library(knitr)
library(ggplot2)
library(countrycode)
library(janitor)
library(ggtext)
library(viridis)
library(rnaturalearth)
library(sf)

# Load and clean data
meat <- read_csv("FAOSTAT_data_meat_consumption.csv", show_col_types = FALSE) %>%
  janitor::clean_names()

gdp <- read_csv("GDP.PER.CAPITA.csv", skip = 4, show_col_types = FALSE) %>%
  janitor::clean_names()

# Clean meat data
meat_clean <- meat %>%
  filter(element == "Food supply quantity (kg/capita/yr)") %>%
  group_by(area, year) %>%
  summarise(Meat_kg_per_capita = sum(value, na.rm = TRUE), .groups = "drop") %>%
  rename(Country = area) %>%
  mutate(
    Country = recode(Country,
                     "United States of America" = "United States",
                     "Russian Federation" = "Russia",
                     "Viet Nam" = "Vietnam",
                     "Republic of Korea" = "South Korea",
                     "Iran (Islamic Republic of)" = "Iran",
                     "Egypt, Arab Rep." = "Egypt",
                     "China, mainland" = "China",
                     "United Kingdom of Great Britain and Northern Ireland" = "United Kingdom",
                     "Czechia" = "Czech Republic"
    ),
    year = as.integer(year)
  )

# Clean and reshape GDP data
gdp_clean <- gdp %>%
  filter(indicator_name == "GDP per capita (current US$)") %>%
  rename(Country = country_name) %>%
  select(Country, matches("^x[0-9]{4}$")) %>%
  pivot_longer(
    cols = -Country,
    names_to = "year",
    values_to = "GDP_per_capita"
  ) %>%
  mutate(
    year = as.integer(str_remove(year, "^x")),
    GDP_per_capita = as.numeric(GDP_per_capita)
  ) %>%
  drop_na()

# Merge and clean
combined_data <- inner_join(meat_clean, gdp_clean, by = c("Country", "year")) %>%
  drop_na()


# Exploratory plots and analysis
ggplot(combined_data, aes(x = GDP_per_capita, y = Meat_kg_per_capita)) +
  geom_point(size = 2.5, alpha = 0.7, color = "#0072B2") +
  geom_smooth(method = "loess", se = FALSE, color = "#D55E00", linewidth = 1.3) +
  scale_x_continuous(labels = scales::label_dollar(scale = 0.001, suffix = "K")) +
  scale_y_continuous(labels = scales::label_number(accuracy = 1)) +
  labs(
    title = "Wealthier Nations Eat More Meat, But the Rise Slows",
    subtitle = "Per capita meat consumption rises with GDP, then levels off at higher incomes",
    x = "GDP per Capita (in Thousands of USD)",
    y = "Meat Consumption (kg per Person per Year)"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    plot.subtitle = element_text(size = 13, margin = margin(b = 10)),
    axis.title = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  )
model <- lm(Meat_kg_per_capita ~ log(GDP_per_capita), data = combined_data)
r2 <- summary(model)$r.squared
r2_label <- paste0("R² = ", round(r2, 2))

ggplot(combined_data, aes(x = log(GDP_per_capita), y = Meat_kg_per_capita)) +
  geom_point(aes(size = GDP_per_capita, color = Meat_kg_per_capita), alpha = 0.7) +
  geom_smooth(method = "lm", se = FALSE, color = "red", linewidth = 1.2) +
  scale_color_viridis_c(option = "viridis", name = "Meat\nConsumption") +
  scale_size_continuous(range = c(1, 6), guide = "none") +
  labs(
    title = "Relationship Between GDP and Meat Consumption",
    subtitle = "Bubble size = GDP per capita | Color = Meat consumption",
    x = "Log(GDP per Capita)",
    y = "Meat Consumption (kg/person/year)"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.background = element_rect(fill = "black", color = NA),
    panel.background = element_rect(fill = "black", color = NA),
    panel.grid.major = element_line(color = "gray50"),
    panel.grid.minor = element_blank(),
    axis.title = element_text(color = "white", face = "bold"),
    axis.text = element_text(color = "white"),
    plot.title = element_text(color = "white", face = "bold", size = 16),
    plot.subtitle = element_text(color = "gray90", size = 12),
    legend.text = element_text(color = "white"),
    legend.title = element_text(color = "white")
  ) +
  annotate("label", x = 6.5, y = max(combined_data$Meat_kg_per_capita, na.rm = TRUE), 
           label = r2_label, fill = "white", color = "black", size = 4.5)


combined_data <- combined_data %>%
  mutate(income_group = case_when(
    GDP_per_capita < 4000 ~ "Low Income",
    GDP_per_capita < 12000 ~ "Middle Income",
    TRUE ~ "High Income"
  ))

combined_data$income_group <- factor(combined_data$income_group,
                                     levels = c("Low Income", "Middle Income", "High Income"))

ggplot(combined_data, aes(x = income_group, y = Meat_kg_per_capita, fill = income_group)) +
  geom_boxplot(color = "black", outlier.shape = 21, outlier.fill = "white", outlier.size = 2) +
  scale_fill_manual(values = c(
    "Low Income" = "#F0E442",
    "Middle Income" = "#56B4E9",
    "High Income" = "#D55E00"
  )) +
  labs(
    title = "Higher Incomes, Heavier Plates?",
    subtitle = "Meat consumption rises with income, but the jump is steepest between low and middle income",
    x = "Income Group",
    y = "Meat Consumption (kg per Person per Year)"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    plot.subtitle = element_text(size = 13, margin = margin(b = 10)),
    axis.title = element_text(face = "bold"),
    legend.position = "none"
  )


world <- rnaturalearth::ne_countries(scale = "medium", returnclass = "sf")

combined_data <- combined_data %>%
  mutate(iso3 = countrycode(Country, origin = "country.name", destination = "iso3c"))

map_data <- combined_data %>%
  group_by(iso3) %>%
  summarise(mean_meat = mean(Meat_kg_per_capita, na.rm = TRUE))

world_data <- left_join(world, map_data, by = c("iso_a3" = "iso3"))

ggplot(world_data) +
  geom_sf(aes(fill = mean_meat), color = "gray80", size = 0.1) +
  scale_fill_viridis_c(
    option = "plasma",
    na.value = "gray90",
    name = "Avg. Meat\nConsumption (kg)"
  ) +
  labs(
    title = "Average Meat Consumption by Country",
    subtitle = "Higher meat consumption is generally observed in wealthier nations",
    caption = "Data: FAOSTAT & World Bank"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold", size = 16),
    plot.subtitle = element_text(size = 12),
    legend.title = element_text(face = "bold"),
    axis.text = element_blank(),
    panel.grid = element_blank()
  )

## Lasso Regression
model_data <- combined_data %>%
  mutate(log_gdp = log(GDP_per_capita)) %>%
  filter(is.finite(log_gdp)) %>%
  select(Meat_kg_per_capita, log_gdp)

set.seed(123)
sample_index <- sample(1:nrow(model_data), 0.9 * nrow(model_data))
train <- model_data[sample_index, ]
test <- model_data[-sample_index, ]

x_train <- model.matrix(Meat_kg_per_capita ~ log_gdp, data = train)
x_test <- model.matrix(Meat_kg_per_capita ~ log_gdp, data = test)

y_train <- train$Meat_kg_per_capita
y_test <- test$Meat_kg_per_capita

lasso_cv <- cv.glmnet(x_train, y_train, alpha = 1)
best_lambda <- lasso_cv$lambda.min

preds <- predict(lasso_cv, s = best_lambda, newx = x_test)
rmse_eval <- sqrt(mean((y_test - preds)^2))
rmse_eval

plot(lasso_cv)
abline(v = log(best_lambda), col = "red", lty = 2, lwd = 2)

