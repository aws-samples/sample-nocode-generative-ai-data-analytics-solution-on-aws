# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import json
from typing import Any, Iterable

import boto3
from aws_lambda_powertools import Logger
from boto3.dynamodb.conditions import Key
from codeinterpreter_lib.aws_helpers.ddb_helper import DDBHelper
from codeinterpreter_lib.aws_helpers.s3_helper import S3Helper
from codeinterpreter_lib.model.core import Message, Role, SessionStatus

logger = Logger(level="INFO")
ddb_helper = DDBHelper()
s3_helper = S3Helper()


DDB_RESOURCE = boto3.resource("dynamodb")
S3_CLIENT = boto3.client("s3")


class DynamoDBMessageStorage:
    """
    Manages the storage and retrieval of messages in a DynamoDB table.

    This class provides methods to load, append, and manage messages for a specific session. It
    handles the conversion of message objects to and
    from the DynamoDB table format. It also supports the storage and retrieval of image messages,
    where the image data is stored in an S3 bucket and the message references the file name.
    """

    def __init__(
        self,
        user_id: str,
        session_id: str,
    ):
        """
        Initialize the DynamoDBMessageStorage instance.
        """
        self.session_id = session_id
        self.user_id = user_id
        self.messages: list[Message] = []

    def get_messages(self) -> list[Message]:
        """
        Get the list of messages for the current session.

        Returns:
            list: A list of messages.
        """
        return self.messages

    def get_conversation_history(self) -> list[dict[str, Any]]:
        """
        Get the conversation history for the current session from user and assistant.

        Returns:
            list: A list of messages prepared for Bedrock Agent interface.
        """
        messages = [m for m in self.messages if m.role in [Role.USER, Role.ASSISTANT]]

        response = []
        for msg in messages:
            if isinstance(msg.content, list):
                # response.append({"role": msg.role.value, "content": msg.content})
                response.append(
                    {
                        "role": msg.role.value,
                        "content": [{"text": json.dumps(msg.content)}],
                    }
                )  # workaround for Bedrock API, does not allow multiple elements in one message atm
            elif isinstance(msg.content, dict):
                response.append({"role": msg.role.value, "content": [msg.content]})
            else:
                response.append(
                    {"role": msg.role.value, "content": [{"text": str(msg.content)}]}
                )

        # last message here needs to be from assistant for Bedrock
        if len(response) > 0 and response[-1]["role"] == "user":
            response.append({"role": "assistant", "content": [{"text": "..."}]})

        return response

    def load_messages(self) -> None:
        """
        Retrieve the messages for the current session from the DynamoDB messages table.

        This method retrieves the messages from the DynamoDB table, converts them to the appropriate message objects, and stores them in the `messages` attribute. If the message content contains an image URL, it retrieves the image data from S3.
        """
        logger.info(
            f"Retrieving messages from DynamoDB using session id ==> {self.session_id}"
        )

        ddb_messages: list[Message] = ddb_helper.query_table(
            table=ddb_helper.messages_table,
            key_condition_expression=Key("session_id").eq(self.session_id),
            response_type=Message,
            scan_index_forward=True,
        )

        for message in ddb_messages:
            self.__local_append_message(message)
        logger.debug("Retrieved messages", messages=self.messages)

    def __local_append_message(self, message: Message) -> None:
        # only store USER and ASSISTANT messages locally
        if message.role not in [Role.USER, Role.ASSISTANT]:
            return

        # if there is two of the same message types in a row (e.g., user - user) merge them
        elif len(self.messages) >= 1 and message.role == self.messages[-1].role:
            self.messages[-1].content = self._merge_content(
                self.messages[-1].content, message.content
            )
        else:
            self.messages.append(message)

    def _merge_content(self, *args: Iterable[str | dict | list]) -> list:
        response = []

        for arg in args:
            if isinstance(arg, list):
                response.extend(arg)
            elif isinstance(arg, dict):
                response.append(arg)
            else:
                response.append({"text": str(arg)})

        return response

    def __ddb_append_message(self, message: Message) -> None:
        ddb_messages: list[Message] = []

        if isinstance(message.content, str):
            ddb_messages.append(message)
        elif isinstance(message.content, list):
            for item in message.content:
                if isinstance(item, str):
                    ddb_messages.append(message)
                else:
                    raise ValueError(
                        f"Content items must be str, instead was: {type(item)}"
                    )
        else:
            raise ValueError("message content must be str or list of dicts")

        try:
            for ddb_message in ddb_messages:
                # store to messages table
                ddb_helper.put_item(table=ddb_helper.messages_table, item=ddb_message)
                logger.info(
                    "Message added to DynamoDB", ddb_message=ddb_message.model_dump()
                )
        except DDB_RESOURCE.meta.client.exceptions.ClientError as e:
            logger.warning("Error adding message to DynamoDB", exc_info=True)
            raise e

    def append_message(self, message: Message) -> None:
        """
        Append a message to the local list of messages and store it in the DynamoDB messages table.

        Args:
            message: The message to be appended.
        """
        self.__ddb_append_message(message)
        self.__local_append_message(message)

    def set_session_status(
        self,
        status_message: str | None = None,
        status: SessionStatus = SessionStatus.PENDING,
    ) -> None:
        ddb_helper.update_session(
            user_id=self.user_id,
            session_id=self.session_id,
            status=status,
            status_message=status_message,
        )
