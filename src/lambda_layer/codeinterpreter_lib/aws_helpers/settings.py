# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""Settings for misc services."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class DynamoDBSettings(BaseSettings):
    """Settings for DynamoDB."""

    model_config = SettingsConfigDict(env_prefix="DDB_")

    TTL_ATTRIBUTE: str
    SESSIONS_TABLE_NAME: str
    MESSAGES_TABLE_NAME: str


class S3Settings(BaseSettings):
    """Settings for S3."""

    model_config = SettingsConfigDict(env_prefix="S3_")

    FILE_STORAGE_BUCKET_NAME: str | None = None
    FILE_STORAGE_BUCKET_KMS_KEY_ARN: str | None = None


class LambdaSettings(BaseSettings):
    """Settings for Lambdas"""

    model_config = SettingsConfigDict(env_prefix="LAMBDA_")

    AGENT_SERVICE_FUNCTION_NAME: str | None = None
    CODE_EXECUTION_FUNCTION_NAME: str | None = None


class BedrockSettings(BaseSettings):
    """Settings for Bedrock."""

    model_config = SettingsConfigDict(env_prefix="BEDROCK_")

    AWS_REGION: str
    AGENT_ID: str
    AGENT_ALIAS: str


class IAMSettings(BaseSettings):
    """Settings for IAM."""

    model_config = SettingsConfigDict(env_prefix="IAM_")

    TEMPORARY_ROLE_ARN: str
