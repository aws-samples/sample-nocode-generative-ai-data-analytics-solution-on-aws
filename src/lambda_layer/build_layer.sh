#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -e

# Extract arguments from inputs
eval "$(jq -r '@sh "LAYER_LOC=\(.layer_loc) PYTHON_VERSIONS=\(.python_versions) REQUIREMENTS_FILE=\(.requirements_file) PYTHON_FOLDERS=\(.python_folders)"')"

declare -a lambda_installed_packages=("urllib3" "python-dateutil" "jmespath" "simplejson")

# Create a folder and go into it
mkdir -p "$LAYER_LOC"
cd "$LAYER_LOC"
#find . -mindepth 1 -delete # clear directory

# Set the size limit
SIZE_LIMIT_MB=240
TOTAL_SIZE_MB=0
# Iterate over the list of Python versions and create library folders
# shellcheck disable=SC2153
for PYTHON_VERSION in $PYTHON_VERSIONS; do
  # Create folder where packages will be installed to
  TARGET_FOLDER="python/lib/${PYTHON_VERSION}/site-packages"
  mkdir -p "${TARGET_FOLDER}"

  # Install packages from requirements file
  pip3 install -r "${REQUIREMENTS_FILE}" --target "${TARGET_FOLDER}" --python-version "${PYTHON_VERSION/python/}" --platform manylinux2014_aarch64 --implementation cp --only-binary=:all: --no-cache-dir --ignore-installed --quiet #--no-deps

  # remove Lambda runtime libs, keep layer smaller
  for i in "${lambda_installed_packages[@]}"; do
    #echo $i
    find "$TARGET_FOLDER" -maxdepth 1 -name "${i}*" -type d -exec rm -r {} \;
  done

  # Copy python folders
  cp -r "$PYTHON_FOLDERS" "$TARGET_FOLDER/"

  # Calculate the size of the folder
  FOLDER_SIZE_MB=$(du -sm "${TARGET_FOLDER}" | cut -f1)

  # Check if the folder size exceeds the limit
  if [ "$FOLDER_SIZE_MB" -gt "$SIZE_LIMIT_MB" ]; then
    echo "Error: The size of the folder ${TARGET_FOLDER} is greater than ${SIZE_LIMIT_MB} MB. Lambda does not support this."
    exit 1
  fi

  # Add folder size to the total size
  TOTAL_SIZE_MB=$((TOTAL_SIZE_MB + FOLDER_SIZE_MB))
done

# Check if the total size exceeds the limit
if [ "$TOTAL_SIZE_MB" -gt "$SIZE_LIMIT_MB" ]; then
  echo "Error: The total size of the Python folders is greater than ${SIZE_LIMIT_MB} MB. Lambda does not support this."
  exit 1
fi

# Output location. An output is required by external
jq -n --arg layer_loc "$LAYER_LOC" "{\"layer_loc\":\$layer_loc}"
