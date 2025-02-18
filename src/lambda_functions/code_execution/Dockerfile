# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

FROM public.ecr.aws/lambda/python:3.12

ENV WORKDIR=./lambda_functions/code_execution

# NOT SURE IF libgomp is needed here
RUN  dnf install -y libgomp &&\
     pip3 install --no-cache-dir --upgrade pip &&\
     pip3 install --no-cache-dir build &&\
     dnf clean all &&\
     rm -rf /var/cache

COPY $WORKDIR/requirements.txt ./
RUN pip3 install --no-cache-dir -r requirements.txt -t .

RUN mkdir -p tmp

COPY $WORKDIR/src ./
COPY ./lambda_layer/codeinterpreter_lib ./codeinterpreter_lib

# TODO: some caching if required
#ENV TIKTOKEN_CACHE_DIR tmp/tiktoken_cache
#RUN mkdir -p $TIKTOKEN_CACHE_DIR
#RUN python3 docker_init.py

# Set user
USER nobody
HEALTHCHECK NONE

CMD ["handler.lambda_handler"]
