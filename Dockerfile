FROM r-base

RUN apt-get -y update && apt-get install -y tzdata && \
    apt-get install -y --no-install-recommends \
        wget \
        libcurl4-openssl-dev \
        libsodium-dev \
        curl \
        apt-transport-https \
        ca-certificates

RUN R -e "install.packages(c('readr', 'curl', 'ggplot2', 'dplyr', 'stringr', 'fable', 'tsibble', 'dplyr', 'feasts', 'remotes', 'urca', 'sodium', 'plumber', 'jsonlite'))"

COPY fable_sagemaker.r /opt/
WORKDIR /opt/

ENTRYPOINT ["/usr/bin/Rscript", "/opt/fable_sagemaker.r", "--no-save"]
