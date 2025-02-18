#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0


SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if ! command -v streamlit &> /dev/null
then
    echo "streamlit could not be found, will install requirements file"
    pip3 install -r "$SCRIPT_DIR/requirements.txt"
fi


if [[ ! -z "${API_BASE_PATH}" ]]; then
    echo "Using API_BASE_PATH from environment"
    API_BASE_PATH="$API_BASE_PATH"
else
    echo "Reading API_BASE_PATH from terraform state"
    API_BASE_PATH=$(terraform -chdir="$SCRIPT_DIR/../terraform" output -raw api_base_path)
fi

echo "Starting streamlit app with API_BASE_PATH=$API_BASE_PATH"

API_BASE_PATH="$API_BASE_PATH" streamlit run "$SCRIPT_DIR/app/chat_interface.py" "$@"
