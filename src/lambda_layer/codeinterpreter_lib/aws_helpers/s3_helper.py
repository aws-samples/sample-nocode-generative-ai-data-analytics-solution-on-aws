# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""Helper function related to AWS S3."""

import mimetypes
import os
import re
from typing import Any

import boto3
from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.event_handler.exceptions import (
    BadRequestError,
    NotFoundError,
)
from botocore.config import Config
from botocore.exceptions import ClientError
from codeinterpreter_lib.model.api import FileDescription
from codeinterpreter_lib.model.core import Role
from .settings import S3Settings

tracer = Tracer()
logger = Logger()

SESSION_KEY_PATTERN = "sessions/{session_id}/"
SESSION_FILES_KEY_PATTERN = "sessions/{session_id}/files/{filename}"
S3_ROLE_TAG_NAME = "codeinterpreter-upload-role"
S3_AGENT_LOADED_TAG_NAME = "codeinterpreter-loaded-in-agent-context"

S3_META_HEADER_PREFIX = "x-amz-meta-"


class S3Helper:
    def __init__(self, credentials: dict | None = None):
        self.s3_settings = S3Settings()  # type: ignore
        self.credentials = credentials

        kwargs = {}
        if self.credentials:
            kwargs.update(self.credentials)
        self.s3_client = boto3.client("s3", **kwargs)
        self.s3_bucket = boto3.resource("s3", **kwargs).Bucket(
            self.s3_settings.FILE_STORAGE_BUCKET_NAME  # type: ignore
        )
        self.s3_client_presigned_urls = self.__get_s3_client_presigned_urls()

    def __get_s3_client_presigned_urls(self):
        s3_client = boto3.client(
            "s3",
            endpoint_url=f"https://{self.s3_settings.FILE_STORAGE_BUCKET_NAME}",
            verify=False,  # TODO: enable SSL verification
            config=Config(s3={"addressing_style": "virtual"}, signature_version="s3v4"),
        )

        s3_client.meta.events.register(
            "before-sign.s3.GetObject", self.strip_bucket_from_path
        )
        s3_client.meta.events.register(
            "before-sign.s3.HeadObject", self.strip_bucket_from_path
        )
        s3_client.meta.events.register(
            "before-sign.s3.PutObject", self.strip_bucket_from_path
        )
        return s3_client

    def strip_bucket_from_path(self, *, request: Any, **_kw):
        """Strips the bucket name from the path.

        Our requests are proxied through an ALB, and we have the domain name matching the bucket name.
        This can currently not be handled by boto3 and we need to manually alter the URL before signing the request
        from: https://private-s3-vpce.example.com/private-s3-vpce.example.com/test.html
        to: https://private-s3-vpce.example.com/test.html

        Args:
            request (Any): _description_
        """
        request.url = re.sub(
            rf"(https:\/\/[^\/]*)(\/{self.s3_settings.FILE_STORAGE_BUCKET_NAME})",
            r"\1",
            request.url,
        )

    def download_session_files(self, session_id: str, target_dir: str):
        session_prefix = SESSION_FILES_KEY_PATTERN.format_map(
            {"session_id": session_id, "filename": ""}
        )
        logger.debug(
            f"Downloading session files from {session_prefix=} to {target_dir=}"
        )

        list_objects_response = self.s3_client.list_objects_v2(
            Bucket=self.s3_settings.FILE_STORAGE_BUCKET_NAME,  # type: ignore
            Prefix=session_prefix,
        ).get("Contents", [])

        for obj in list_objects_response:
            if "Key" in obj:
                target_filepath = os.path.join(
                    target_dir, obj["Key"].removeprefix(session_prefix)
                )
                logger.debug(f"Downloading file from {obj['Key']} to {target_filepath}")
                self.s3_bucket.download_file(obj["Key"], target_filepath)
                # obj_body = self.s3_client.get_object(
                #     Bucket=self.s3_settings.FILE_STORAGE_BUCKET_NAME, Key=obj["Key"]
                # )["Body"]
                # with open(target_filepath, "wb") as f:
                #     for chunk in obj_body.iter_chunks(chunk_size=4096):
                #         f.write(chunk)

    def upload_local_file(
        self,
        session_id: str,
        filename: str,
        local_filepath: str,
        role: Role = Role.ASSISTANT,
    ):
        key = SESSION_FILES_KEY_PATTERN.format_map(
            {"session_id": session_id, "filename": filename}
        )
        logger.debug(f"Uploading {local_filepath=} to {key=}")

        metadata = {S3_ROLE_TAG_NAME: role.value}
        extra_args: dict[str, Any] = {"Metadata": metadata}
        mime_type, _ = mimetypes.guess_type(filename)

        if mime_type is not None:
            extra_args["ContentType"] = mime_type

        with open(local_filepath, "rb") as f:
            self.s3_client.put_object(
                Bucket=self.s3_settings.FILE_STORAGE_BUCKET_NAME,  # type: ignore
                Key=key,
                Body=f,
                **extra_args,
            )

    @tracer.capture_method
    def create_presigned_upload_url(
        self,
        session_id: str,
        filename: str,
        fields=None,
        conditions=None,
        expiration=3600,
    ):
        """Generate a presigned URL S3 POST request to upload a file

        :param session_id: string
        :param filename: string
        :param fields: dictionary of prefilled form fields
        :param conditions: list of conditions to include in the policy
        :param expiration: Time in seconds for the presigned URL to remain valid
        :return: dictionary with the following keys:
            url: URL to post to
            fields: dictionary of form fields and values to submit with the POST
        :return: None if error.
        """

        # Generate a presigned S3 POST URL

        key = SESSION_FILES_KEY_PATTERN.format_map(
            {"session_id": session_id, "filename": filename}
        )

        logger.debug(
            f"Checking if file exists and creating presigned upload URL for {key=}"
        )
        try:
            self.s3_client.head_object(
                Bucket=self.s3_settings.FILE_STORAGE_BUCKET_NAME,  # type: ignore
                Key=key,
            )
        except ClientError as e:
            if e.response.get("Error", {}).get("Code") == "404":
                logger.debug(
                    f"File with {key=} does not exist. Creating presigned upload URL."
                )

                try:
                    response = self.s3_client_presigned_urls.generate_presigned_post(
                        self.s3_settings.FILE_STORAGE_BUCKET_NAME,  # type: ignore
                        Key=key,
                        Fields=fields,
                        Conditions=conditions,
                        ExpiresIn=expiration,
                    )
                except ClientError as client_error:
                    logger.exception(client_error)
                    return None

                # The response contains the presigned URL and required fields
                return response
            else:
                raise e

        raise BadRequestError(f"File with {filename=} already exists")

    @tracer.capture_method
    def create_presigned_download_url(
        self, session_id: str, filename: str, expiration=3600
    ):
        """Generate a presigned URL S3 GET request to download a file

        :param session_id: string
        :param filename: string
        :param expiration: Time in seconds for the presigned URL to remain valid
        :return: None if error.
        """
        # Generate a presigned S3 POST URL

        key = SESSION_FILES_KEY_PATTERN.format_map(
            {"session_id": session_id, "filename": filename}
        )

        try:
            self.s3_client.head_object(
                Bucket=self.s3_settings.FILE_STORAGE_BUCKET_NAME,  # type: ignore
                Key=key,
            )
        except ClientError as e:
            if e.response.get("Error", {}).get("Code") == "404":
                raise NotFoundError(f"File with {key=} does not exist")
            else:
                raise e

        try:
            url = self.s3_client_presigned_urls.generate_presigned_url(
                "get_object",
                Params={
                    "Bucket": self.s3_settings.FILE_STORAGE_BUCKET_NAME,
                    "Key": key,
                },
                ExpiresIn=expiration,
            )
        except ClientError as e:
            logger.exception(e)
            return None

        # The response contains the presigned URL
        return {"url": url}

    @tracer.capture_method
    def list_session_files(
        self, session_id: str, user_only: bool = True
    ) -> list[FileDescription]:
        """list all files in a session

        :param session_id: string
        :param user_only: bool
        :return: list of FileDescription objects
        """
        s3_objects = self.s3_bucket.objects.filter(
            Prefix=SESSION_KEY_PATTERN.format_map({"session_id": session_id})
        )
        logger.debug("Loaded S3 objects.", s3_objects=s3_objects)

        file_descriptions = []
        for s3_object in s3_objects:
            file_description = FileDescription(
                s3_location=f"s3://{self.s3_settings.FILE_STORAGE_BUCKET_NAME}/{s3_object.key}",
                filename=s3_object.key.split("/")[-1],
                size=s3_object.size,
            )

            if not user_only:
                file_descriptions.append(file_description)
                continue
            else:  # filter for files with user tag
                s3_object_metadata = self.s3_client.head_object(
                    Bucket=self.s3_settings.FILE_STORAGE_BUCKET_NAME,  # type: ignore
                    Key=s3_object.key,
                )
                logger.debug(
                    "Loaded S3 object metadata.",
                    s3_object_metadata=s3_object_metadata,
                )

                if s3_object_metadata["Metadata"].get(S3_ROLE_TAG_NAME) == Role.USER:
                    file_descriptions.append(file_description)

        return file_descriptions

    @tracer.capture_method
    def clear_session_files(self, session_id: str):
        """Delete all files associated with a session from S3.

        Args:
            session_id (str): The unique identifier for the session whose files should be deleted

        Returns:
            The response from S3 delete operation

        """
        return self.s3_bucket.objects.filter(
            Prefix=SESSION_KEY_PATTERN.format_map({"session_id": session_id})
        ).delete()
