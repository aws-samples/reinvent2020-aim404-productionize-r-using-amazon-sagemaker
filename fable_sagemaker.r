## Dependencies ##  install.packages(c('readr', 'curl', 'ggplot2', 'dplyr', 'stringr', 'fable', 'tsibble', 'dplyr', 'feasts', 'remotes', 'urca', 'sodium', 'plumber', 'jsonlite'))

## From prototype script to SageMaker-ready script
#  1. Make the script aware of how SageMaker places the input and config files
#  2. Refactor the code into "train", "evaluate" and "serve" as that how SageMaker 
#     execute the codes from the container for training, evaluating and serving 
#     the model.
library(fable)
library(tsibble)
library(dplyr)
library(jsonlite) # Library to read json
library(ggplot2)

## Container directories
# /opt/ml
# |-- input
# |   |-- config
# |   |   |-- hyperparameters.json
# |   |   `-- resourceConfig.json
# |   `-- data
# |       `-- <channel_name>
# |           `-- <input data>
# |-- model
# |   `-- <model files>
# |-- processing (if with SageMaker Processing)
#     `-- input
#     `-- output
# `-- output
#     `-- failure

## Assigning paths
prefix <- '/opt/ml'
input_path <- file.path(prefix, 'input', 'data')
training_data_path <- file.path(input_path, 'train')
output_path <- file.path(prefix, 'output')
model_path <- file.path(prefix, 'model')
param_path <- file.path(prefix, 'input', 'config', 'hyperparameters.json')

processing_path <- file.path(prefix, 'processing')
processing_input_path <- file.path(processing_path, 'input')
processing_output_path <- file.path(processing_path, 'output')

train <- function() {
  ## Extract (hyper)parameters
  training_params <- read_json(param_path)
  if (!is.null(training_params$city)) {
    city <- training_params$city}
  else {
    city <- 'Melbourne'}
  if (!is.null(training_params$ets_trend_method)) {
    ets_trend_method <- training_params$ets_trend_method}
  else {
    # Use Additive method by default
    ets_trend_method <- 'A'}
  # information criteria c('aicc', 'aic', 'bic')
  if (!is.null(training_params$ic)) {
    ic <- training_params$ic}
  else {
    ic <- 'aic'}
  
  ## Getting data from local path that is downloaded from S3
  training_file <- list.files(training_data_path, full.names=TRUE)
  print(training_file)
  training_data <- readRDS(training_file)
  
  tourism_city <- training_data %>%
    filter(Region == city)
  
  tourism_city %>%
    group_by(Purpose) %>%
    slice(1)
  
  ## Training ETS and ARIMA models
  fitted_model <- tourism_city %>%
    model(
      ets = ETS(Trips ~ trend(ets_trend_method), ic = ic),
      arima = ARIMA(Trips, ic = ic)
    )
  fitted_model
  
  ## Saving the model
  save(fitted_model, file = file.path(model_path,'model.rdata'))

  ## Print out model accuracy
  print(fitted_model %>%
          accuracy() %>%
          arrange(MASE)
        )
  }

# Evaluate the model and generate report
evaluate <- function(city) {
  
  ## Load model
  model_file <- file.path(processing_input_path, 'model.tar.gz')
  system(sprintf('tar zxvf %s', model_file))
  load('model.rdata')
  
  ## Load input data
  print(city)
  tourism_city <- tourism %>%
    filter(Region == city)
  
  tourism_city %>%
    group_by(Purpose) %>%
    slice(1)
  
  ## Analysis
  accuracy_report <- fitted_model %>%
                        accuracy() %>%
                        arrange(MASE)
  print(accuracy_report)
  write.csv(accuracy_report, file.path(processing_output_path, 
                                       'forecast-accuracy-report.csv'))
  
  fc <- fitted_model %>%
    forecast(h = "5 years")
  
  fc %>%
    hilo(level = c(80, 95))
  fc
  
  fc %>%
    autoplot(tourism_city)
  
  ggsave(file.path(processing_output_path,  'forecast-report.png'))
  }

# Run at start-up
args <- commandArgs(trailingOnly = TRUE)
if (any(grepl('train', args))) {
  # How SageMaker run your training script:
  # https://docs.aws.amazon.com/sagemaker/latest/dg/your-algorithms-training-algo-dockerfile.html
  train()
}

if (any(grepl('evaluate', args))) {
  # How SageMaker run your processing script:
  # https://docs.aws.amazon.com/sagemaker/latest/dg/build-your-own-processing-container.html
  evaluate(args[2])
}
