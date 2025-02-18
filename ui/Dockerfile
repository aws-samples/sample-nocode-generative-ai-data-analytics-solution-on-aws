# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

FROM public.ecr.aws/docker/library/python:3.12-slim


RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    software-properties-common \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN pip3 install --no-cache-dir -r requirements.txt

WORKDIR /app
COPY app/* ./app/

EXPOSE 8501
USER nobody
HEALTHCHECK CMD ["curl", "--fail", "http://localhost:8501/_stcore/health"]

ENTRYPOINT ["streamlit", "run", "app/chat_interface.py", "--server.port=8501", "--server.address=0.0.0.0"]
