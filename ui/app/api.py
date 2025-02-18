# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import functools
import os
import time
from dataclasses import dataclass
from typing import Literal

import requests
import streamlit as st
from streamlit.logger import get_logger

logger = get_logger(__name__)

API_BASE_PATH = os.environ["API_BASE_PATH"].removesuffix("/")
POLLING_INTERVAL = 1
USER_ID_HEADER_NAME = "X-Code-Interpreter-User-Id"

logger.info(f"Initialized with {API_BASE_PATH=}")


@dataclass
class Message:
    role: Literal["user", "assistant", "trace", "tool"]
    content: str
    timestamp: float

    @property
    def internal(self) -> bool:
        return self.role not in ["user", "assistant"]


class SessionManager:
    def __response_hook(self, r: requests.Response, *args, **kwargs):
        try:
            r.raise_for_status()
        except requests.HTTPError as http_error:
            logger.warning(
                f"Error in request with response headers {r.headers} and content {r.content!r}"
            )
            logger.warning(
                f"Error in request with request headers {r.request.headers} and body {r.request.body!r}",
                exc_info=True,
            )
            raise http_error

    def __init__(self, user_id: str):
        self.session_id = None
        self.assistant_status = "ready"
        self.error = None
        self.requests_session = requests.Session()
        self.requests_session.headers[USER_ID_HEADER_NAME] = user_id

        self.requests_session.hooks = {
            "response": self.__response_hook,
        }

        self.requests_session.request = functools.partial(  # type: ignore
            self.requests_session.request, timeout=10
        )  # globally overrides request timeout
        self.messages: list[Message] = []
        # logger.info(f"Sessions: {self.get_sessions()}")
        self.create_session()

    def get_messages(self):
        return self.messages

    def __ensure_session(self):
        if not self.session_id:
            self.create_session()

    def create_session(self):
        st.cache_data.clear()
        self.session_id = self.requests_session.post(
            f"{API_BASE_PATH}/sessions"
        ).json()["session_id"]
        logger.info(f"Created session with ID {self.session_id}")
        return self.session_id

    def reset_session(self):
        logger.info(f"Resetting session with ID {self.session_id}")
        if self.session_id:
            self.delete_session()
            self.session_id = None
            self.messages.clear()
            self.assistant_status = "ready"

    def get_session(self, **kwargs):
        return self.requests_session.get(
            f"{API_BASE_PATH}/sessions/{self.session_id}", params=kwargs
        ).json()

    def get_sessions(self, **kwargs):
        return self.requests_session.get(
            f"{API_BASE_PATH}/sessions", params=kwargs
        ).json()

    def delete_session(self):
        logger.info(f"Deleting session with ID {self.session_id}")
        return self.requests_session.delete(
            f"{API_BASE_PATH}/sessions/{self.session_id}"
        )

    def wait_for_new_messages(self) -> tuple[bool, str]:
        self.__ensure_session()
        logger.info(f"Start polling for session with ID {self.session_id}")
        count = 0

        while count < 30:
            response = self.get_session(
                include_messages_from=(
                    0 if not self.messages else self.messages[-1].timestamp
                )
            )
            logger.info(
                f"Received polling response with status '{response['status']}' and message '{response.get('status_message')}'"
            )

            status_message = response.get("status_message")

            updated = False
            if status_message != self.assistant_status:
                self.assistant_status = status_message or "ready"
                if response["status"] == "ERROR":
                    self.error = status_message
                updated = True

            if response.get("messages"):
                for message in response["messages"]:
                    logger.info(f"Received message from {message['role']}")
                    logger.info(message)
                    # if message["role"] in ["user", "assistant"]:
                    self.messages.append(Message(**message))
                updated = True

            if updated or response["status"] != "PENDING":
                return response["status"] == "PENDING"

            time.sleep(POLLING_INTERVAL)  # nosemgrep: arbitrary-sleep

        raise Exception("Polling took too long, aborting")

    def get_session_files(self):
        self.__ensure_session()
        return self.requests_session.get(
            f"{API_BASE_PATH}/sessions/{self.session_id}/files"
        ).json()

    def __get_session_file_upload_params(self, filename):
        self.__ensure_session()
        return self.requests_session.get(
            f"{API_BASE_PATH}/sessions/{self.session_id}/files/upload",
            params={"filename": filename},
        ).json()

    def __get_session_file_download_url(self, filename):
        self.__ensure_session()
        return self.requests_session.get(
            f"{API_BASE_PATH}/sessions/{self.session_id}/files/download",
            params={"filename": filename},
        ).json()["url"]

    def __upload_file_to_s3(self, filedata: bytes, presigned_data: dict):
        url = presigned_data["url"]
        fields = presigned_data["fields"]

        # Prepare the form data
        form_data = {field: value for field, value in fields.items()}
        form_data["file"] = (fields["key"], filedata)

        # Send the POST request
        response = self.requests_session.post(url, files=form_data)

        if response.status_code != 204:
            logger.error(f"Failed to upload file: {response.text}")
            raise RuntimeError("Failed to upload file")
        else:
            logger.debug("Successfully uploaded file")

    def upload_file(self, filename: str, filedata: bytes):
        logger.info(f"Uploading file {filename}")
        upload_params = self.__get_session_file_upload_params(filename)
        self.__upload_file_to_s3(filedata, upload_params)

    @st.cache_data()
    def download_file(_self, filename) -> bytes:
        logger.info(f"Downloading file {filename}")
        download_params = _self.__get_session_file_download_url(filename)
        return _self.requests_session.get(download_params).content

    @st.cache_data()
    def download_file_url(_self, filename) -> str:
        logger.info(f"Get file download url for {filename}")
        return _self.__get_session_file_download_url(filename)

    def post_message(self, content: str):
        self.__ensure_session()
        logger.info(f"Posting user message: {content}")
        return self.requests_session.post(
            f"{API_BASE_PATH}/sessions/{self.session_id}/messages",
            json={"content": content},
        ).json()
