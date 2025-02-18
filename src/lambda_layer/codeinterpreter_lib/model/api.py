# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

from pydantic import BaseModel, Field


class FileDescription(BaseModel):
    s3_location: str | None = Field(exclude=True)
    filename: str
    size: int
