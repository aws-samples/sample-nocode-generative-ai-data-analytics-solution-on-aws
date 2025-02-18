# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""Helper function related to AWS Lambda."""

from functools import cached_property

import boto3
from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.parser import BaseModel
from .settings import LambdaSettings

tracer = Tracer()
logger = Logger()


class LambdaHelper:
    def __init__(self):
        self.lambda_settings = LambdaSettings()

    @cached_property
    def lambda_client(self):
        return boto3.client("lambda")

    def invoke_lambda_async(self, function_name: str, payload: BaseModel):
        logger.info(f"Invoking lambda {function_name} asynchronously.")
        self.lambda_client.invoke(
            FunctionName=function_name,
            InvocationType="Event",
            Payload=payload.model_dump_json(),
        )

    def invoke_lambda_sync(self, function_name: str, payload: BaseModel):
        logger.info(f"Invoking lambda {function_name} synchronously.")
        response = self.lambda_client.invoke(
            FunctionName=function_name,
            InvocationType="RequestResponse",
            Payload=payload.model_dump_json(),
        )
        return response

    def prewarm_lambda_async(self, function_name: str):
        logger.info(f"Prewarming lambda {function_name} with empty event")
        self.lambda_client.invoke(
            FunctionName=function_name,
            InvocationType="Event",
            Payload="{}",
        )
