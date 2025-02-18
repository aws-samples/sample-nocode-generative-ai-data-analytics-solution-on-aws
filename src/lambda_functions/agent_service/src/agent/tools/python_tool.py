# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import json

import boto3
from aws_lambda_powertools import Logger
from codeinterpreter_lib.aws_helpers.lambda_helper import LambdaHelper
from codeinterpreter_lib.aws_helpers.settings import IAMSettings, S3Settings
from codeinterpreter_lib.model.core import (
    AwsCredentials,
    CodeExecutionLambdaInputPayload,
    CodeExecutionLambdaResponsePayload,
)

logger = Logger()

lambda_helper = LambdaHelper()

s3_settings = S3Settings()
iam_settings = IAMSettings()  # type: ignore

sts_client = boto3.client("sts")


class LambdaPythonREPL:
    """External Lambda Python REPL."""

    def __init__(self, session_id) -> None:
        self.session_id = session_id

        # pre-warm code execution Lambda for subsequent calls to be faster
        lambda_helper.prewarm_lambda_async(
            lambda_helper.lambda_settings.CODE_EXECUTION_FUNCTION_NAME  # type: ignore
        )

    def __get_aws_credentials(self) -> AwsCredentials:
        try:
            policy = {
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Action": ["s3:GetObject", "s3:PutObject"],
                        "Resource": f"arn:aws:s3:::{s3_settings.FILE_STORAGE_BUCKET_NAME}/sessions/{self.session_id}/*",
                    },
                    {
                        "Effect": "Allow",
                        "Action": "s3:ListBucket",
                        "Resource": f"arn:aws:s3:::{s3_settings.FILE_STORAGE_BUCKET_NAME}",
                        "Condition": {
                            "StringLike": {"s3:prefix": f"sessions/{self.session_id}/*"}
                        },
                    },
                    {
                        "Effect": "Allow",
                        "Action": ["kms:Decrypt", "kms:GenerateDataKey"],
                        "Resource": s3_settings.FILE_STORAGE_BUCKET_KMS_KEY_ARN,
                    },
                ],
            }

            credentials = sts_client.assume_role(
                RoleArn=iam_settings.TEMPORARY_ROLE_ARN,
                RoleSessionName=f"code-execution-{self.session_id}",
                Policy=json.dumps(policy),
                DurationSeconds=900,  # 900 is the minimum
            )["Credentials"]

            return AwsCredentials(
                aws_access_key_id=credentials["AccessKeyId"],
                aws_secret_access_key=credentials["SecretAccessKey"],
                aws_session_token=credentials["SessionToken"],
            )
        except Exception as error:
            logger.exception(  # nosemgrep: logging-error-without-handling
                "Error in getting credentials"
            )
            raise error

    def run(
        self, code: str, timeout: int | None = None
    ) -> CodeExecutionLambdaResponsePayload:
        code_execution_payload = CodeExecutionLambdaInputPayload(
            session_id=self.session_id,
            code=code,
            timeout=timeout,
            aws_credentials=self.__get_aws_credentials(),
        )

        lambda_response = lambda_helper.invoke_lambda_sync(
            function_name=lambda_helper.lambda_settings.CODE_EXECUTION_FUNCTION_NAME,
            payload=code_execution_payload,
        )

        response_payload = lambda_response["Payload"].read().decode("utf-8")
        try:
            code_execution_response = (
                CodeExecutionLambdaResponsePayload.model_validate_json(response_payload)
            )
        except Exception:
            logger.error(
                f"Failed to parse response from code execution lambda: {
                    response_payload
                }"
            )
            return CodeExecutionLambdaResponsePayload(
                stderr=f"Failed to parse response from code execution lambda: {
                    response_payload
                }",
                stdout="",
                execution_time=-1,
                generated_files=[],
            )

        logger.debug(
            f"Received Lambda response, code execution time was {
                code_execution_response.execution_time:.5f
            } secs",
            response=code_execution_response,
        )
        return code_execution_response
        # return (
        #     (code_execution_response.stderr, True)
        #     if len(code_execution_response.stderr) > 0
        #     else (code_execution_response.stdout, False)
        # )
