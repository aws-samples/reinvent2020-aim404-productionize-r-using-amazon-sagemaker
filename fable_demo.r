## Dependencies 
## install.packages(c('readr', 'curl', 'ggplot2', 'dplyr', 'stringr', 'fable', 'tsibble', 'dplyr', 'feasts', 'remotes', 'urca', 'sodium', 'plumber', 'jsonlite'))
library(fable)
library(tsibble)
library(dplyr)

## Setting parameters
city <- 'Melbourne'
ets_trend_method <- 'A' # additive
ic <- 'aic' # use aic as information criteria to select model

## Getting data
tourism_city <- tourism %>%
  filter(Region == city)
tourism

## Exploration
# Purpose: Business, Holiday, Visiting friends and family, or Others
tourism_city %>%
  autoplot(Trips)

## Training ETS and ARIMA models
fitted_model <- tourism_city %>%
  model(
    ets = ETS(Trips ~ trend(ets_trend_method), ic = ic),
    arima = ARIMA(Trips, ic = ic)
  )
fitted_model

## Inferencing
fc <- fitted_model %>%
  forecast(h = "5 years")
fc

fc %>%
  hilo(level = c(80, 95))

fc %>%
  autoplot(tourism_city)

## Analysis
accuracy_report <- fitted_model %>%
  accuracy() %>%
  arrange(MASE)
print(accuracy_report)