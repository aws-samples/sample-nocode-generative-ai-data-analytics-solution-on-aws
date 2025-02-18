# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import re
import time
from decimal import Decimal
from enum import Enum
from typing import Any, TypedDict

from pydantic import BaseModel, Field, field_serializer


class SessionStatus(str, Enum):
    PENDING = "PENDING"
    DONE = "DONE"
    ERROR = "ERROR"


class Role(str, Enum):
    USER = "user"
    ASSISTANT = "assistant"
    TRACE = "trace"
    TOOL = "tool"


class Session(BaseModel):
    user_id: str
    session_id: str
    status: SessionStatus
    status_message: str | None = None
    ttl: int = -1

    def ddb_key(self) -> dict[str, Any]:
        return {"user_id": self.user_id, "session_id": self.session_id}

    def api_dump(self) -> dict[str, Any]:
        return self.model_dump(exclude_none=True, exclude=set(["user_id"]))


class Message(BaseModel):
    session_id: str
    timestamp: float = Field(..., default_factory=lambda: time.time() * 1000)  # type: ignore
    role: Role
    content: str | dict[str, Any] | list[dict[str, Any]]

    @field_serializer("timestamp")
    def serialize_timestamp(self, timestamp: float, _info) -> Decimal:
        return Decimal.from_float(timestamp)

    def ddb_key(self) -> dict[str, Any]:
        return {
            "session_id": self.session_id,
            "timestamp": self.serialize_timestamp(self.timestamp, None),
        }

    def __sanitize_message_content(self):
        # remove links to local files
        string = str(self.content)  # coming from DynamoDB, this should always be str
        string = re.sub(f"/tmp/{self.session_id}/", r"", string)  # nosec B108
        string = re.sub("<##scratchpad_folder/?##>/?", r"", string)

        return string

    def api_dump(self) -> dict[str, Any]:
        dump = self.model_dump(exclude_none=True, exclude=set(["session_id"]))
        dump["content"] = self.__sanitize_message_content()
        return dump


# Lambda payloads
class AgentServiceLambdaInputPayload(BaseModel):
    session_id: str
    user_id: str
    message: Message


class AwsCredentials(TypedDict):
    aws_access_key_id: str
    aws_secret_access_key: str
    aws_session_token: str


class CodeExecutionLambdaInputPayload(BaseModel):
    session_id: str
    code: str
    timeout: int | None = None
    aws_credentials: AwsCredentials


class CodeExecutionLambdaResponsePayload(BaseModel):
    generated_files: list[str]
    stdout: str
    stderr: str
    execution_time: float
