# setwd("~/data-science-with-r-sagemaker.git/forecasting")

###################################
## Getting libraries
library(reticulate)
sagemaker <- import('sagemaker')
boto3 <- import('boto3')

# Amazon SageMaker runs your code in a container image with the dependencies.
# We build a R container using the shell script that reads the Dockerfile
container <- 'r-fable-trip-forecasting'
tag <- 'latest'
system(sprintf('./build_and_push_docker.sh %s %s', container, tag))

# define cloud resources
session <- sagemaker$Session()
region <- session$boto_region_name
bucket <- 'sagemaker-r-fable-reinvent-demo'
role <- sagemaker$get_execution_role()
account <- boto3$client('sts')$get_caller_identity()$Account

# define training input and output parameters
image <- sprintf('%s.dkr.ecr.%s.amazonaws.com/%s:%s', account, region, container, tag)
output_path <- file.path('s3:/', bucket, container)
hyperparameters = list('city'='Melbourne', 'ets_trend_method' = 'A', 'ic' = 'aic')
input_data_path <- 's3://sagemaker-r-fable-reinvent-demo/tourism_tsbl.rds'
training_input <- sagemaker$TrainingInput(s3_data = input_data_path)

###################################
## Initiate SageMaker Estimator
estimator <- sagemaker$estimator$Estimator(role = role,
                                           image_uri = image,
                                           instance_type = 'ml.m4.xlarge',
                                           instance_count = 1L,
                                           volume_size_in_gb = 5L,
                                           max_run = 3600L,
                                           input_mode = 'File',
                                           base_job_name = 'r-fable-trip-forecasting',
                                           output_path = output_path,
                                           sagemaker_session = session, 
                                           hyperparameters = hyperparameters)

estimator$fit(inputs = list('train'=training_input), 
              wait = FALSE) # wait = FALSE would submit an async job

###################################
## Evaluate the model with Amazon SageMaker Processing, reusing the same container image
processor <- sagemaker$processing$ScriptProcessor(role = role,
                                                  image_uri = image,
                                                  command = list('/usr/bin/Rscript'),
                                                  instance_type = 'ml.t3.large',
                                                  instance_count = 1L,
                                                  volume_size_in_gb = 5L,
                                                  max_runtime_in_seconds = 3600L,
                                                  base_job_name = 'r-fable-evaluation',
                                                  sagemaker_session = session)

# define input/output
output_processing_path <- file.path(output_path, 'evaluation', 'output')
processing_input <- list(sagemaker$processing$ProcessingInput(input_name = 'model-for-evaluate', 
                                                              source = estimator$model_data, 
                                                              destination = '/opt/ml/processing/input'))
processing_output <- list(sagemaker$processing$ProcessingOutput(output_name = 'evaluation-output', 
                                                                source='/opt/ml/processing/output', 
                                                                destination = output_processing_path))
result=processor$run(code = 'fable_sagemaker.r',
                     inputs = processing_input,
                     outputs = processing_output,
                     arguments = list('evaluate', hyperparameters$city),
                     wait = FALSE)

###################################
## Execute a StepFunctions workflow by uploading a file to S3 bucket
# https://us-west-2.console.aws.amazon.com/states/home?region=us-west-2#/statemachines/view/arn:aws:states:us-west-2:029454422462:stateMachine:r-fable-sagemaker-training-approval
s3_client <- boto3$client('s3')
s3_client$upload_file('/home/ubuntu/data-science-with-r-sagemaker.git/forecasting/data/tourism/tourism_tsbl.rds', 
                      bucket,
                      'data/tourism_tsbl.rds')
