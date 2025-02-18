# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""Helper function related to AWS DynamoDB."""

import datetime
from functools import cached_property, lru_cache
from typing import TYPE_CHECKING, Any, Type, TypeVar, overload

import boto3
from aws_lambda_powertools import Logger, Tracer
from boto3.dynamodb.conditions import ConditionBase, Key
from botocore.exceptions import ClientError
from codeinterpreter_lib.model.core import Message, Session, SessionStatus
from pydantic import BaseModel
from .settings import DynamoDBSettings

tracer = Tracer()
logger = Logger()

T = TypeVar("T", bound=BaseModel)

TTL_7_DAYS_IN_SECONDS = 60 * 60 * 24 * 7
TTL_30_DAYS_IN_SECONDS = 60 * 60 * 24 * 30

if TYPE_CHECKING:
    from mypy_boto3_dynamodb.service_resource import _Table


class DDBHelper:
    def __init__(self) -> None:
        self.ddb_settings = DynamoDBSettings()  # type: ignore

    @cached_property
    def sessions_table(self) -> "_Table":
        return boto3.resource("dynamodb").Table(self.ddb_settings.SESSIONS_TABLE_NAME)

    @cached_property
    def messages_table(self) -> "_Table":
        return boto3.resource("dynamodb").Table(self.ddb_settings.MESSAGES_TABLE_NAME)

    def get_ttl(self, seconds: int = TTL_7_DAYS_IN_SECONDS) -> int:
        return int(datetime.datetime.now().timestamp()) + seconds

    def put_item(self, table: "_Table", item: dict | BaseModel):
        if isinstance(item, BaseModel):
            item = item.model_dump(
                exclude_none=True,
                include=item.model_fields.keys(),  # type: ignore
            )  # make sure to always include all fields when dumping to DDB

        response = table.put_item(Item=item)
        return response

    @overload
    def get_item(
        self, table: "_Table", key: dict, response_type: Type[T]
    ) -> T | None: ...

    @overload
    def get_item(self, table: "_Table", key: dict) -> dict[str, Any] | None: ...

    def get_item(
        self, table: "_Table", key: dict, response_type: Type[T] | None = None
    ) -> T | dict[str, Any] | None:
        response = table.get_item(Key=key)
        if "Item" not in response:
            return None
        elif response_type is not None and "Item" in response:
            return response_type.model_validate(response["Item"])
        else:
            return response.get("Item")

    @overload
    def update_item(
        self,
        table: "_Table",
        key: dict,
        update_expression: str,
        expression_attribute_values: dict,
        expression_attribute_names: dict,
        *,
        return_values: str = "NONE",
    ) -> dict[str, Any]: ...

    @overload
    def update_item(
        self,
        table: "_Table",
        key: dict,
        update_expression: str,
        expression_attribute_values: dict,
        expression_attribute_names: dict,
        response_type: Type[T],
        return_values: str = "NONE",
    ) -> T: ...

    def update_item(
        self,
        table: "_Table",
        key: dict,
        update_expression: str,
        expression_attribute_values: dict,
        expression_attribute_names: dict,
        response_type: Type[T] | None = None,
        return_values: str = "NONE",
    ) -> T | dict[str, Any]:
        response = table.update_item(
            Key=key,
            UpdateExpression=update_expression,
            ExpressionAttributeValues=expression_attribute_values,
            ExpressionAttributeNames=expression_attribute_names,
            ReturnValues=return_values,  # type: ignore
        )
        if response_type is not None:
            return response_type.model_validate(response["Attributes"])
        else:
            return response  # type: ignore

    def delete_item(self, table: "_Table", key: dict, return_values: str = "NONE"):
        response = table.delete_item(Key=key, ReturnValues=return_values)  # type: ignore
        return response

    @overload
    def query_table(
        self,
        table: "_Table",
        response_type: Type[T],
        key_condition_expression: str | ConditionBase | None = None,
        filter_expression: str | ConditionBase | None = None,
        index_name: str | None = None,
        scan_index_forward: bool | None = None,
    ) -> list[T]: ...

    @overload
    def query_table(
        self,
        table: "_Table",
        *,
        key_condition_expression: str | ConditionBase | None = None,
        filter_expression: str | ConditionBase | None = None,
        index_name: str | None = None,
        scan_index_forward: bool | None = None,
    ) -> dict[str, Any]: ...

    def query_table(
        self,
        table: "_Table",
        response_type: Type[T] | None = None,
        key_condition_expression: str | ConditionBase | None = None,
        filter_expression: str | ConditionBase | None = None,
        index_name: str | None = None,
        scan_index_forward: bool | None = None,
    ) -> list[T] | dict:
        query_args = {}
        if key_condition_expression is not None:
            query_args["KeyConditionExpression"] = key_condition_expression
        if filter_expression is not None:
            query_args["FilterExpression"] = filter_expression
        if index_name is not None:
            query_args["IndexName"] = index_name
        if scan_index_forward is not None:
            query_args["ScanIndexForward"] = scan_index_forward  # type: ignore

        response = table.query(**query_args)  # type: ignore
        if response_type is None:
            return response  # type: ignore
        else:
            return [response_type.model_validate(i) for i in response["Items"]]

    @lru_cache
    @tracer.capture_method
    def is_user_allowed_to_access_session(self, user_id: str, session_id: str) -> bool:
        """
        Check if the user is allowed to access the session.

        Args:
            user_id (str): The question number.
            session_id (str): The session ID.

        Returns:
            bool: True if the user is allowed to access the session, False otherwise.
        """

        try:
            response = self.get_item(
                table=self.sessions_table,
                key={"user_id": user_id, "session_id": session_id},
            )
        except ClientError as e:
            if e.response.get("Error", {}).get("Code") == "ResourceNotFoundException":
                return False
            else:
                raise e

        return response is not None

    @tracer.capture_method
    def clear_session_messages(self, session_id: str):
        """
        Clear the chat history for a given session.

        Args:
            session_id (str): The session ID.
        """
        messages: list[Message] = self.query_table(
            table=self.messages_table,
            key_condition_expression=Key("session_id").eq(session_id),
            response_type=Message,
        )
        logger.debug(f"Deleting {len(messages)} messages from table.")
        with self.messages_table.batch_writer() as batch:
            for message in messages:
                batch.delete_item(Key=message.ddb_key())

    def update_session(
        self,
        user_id: str,
        session_id: str,
        status: SessionStatus,
        status_message: str | None = None,
    ) -> Session:
        return self.update_item(
            table=self.sessions_table,
            key={"user_id": user_id, "session_id": session_id},
            update_expression="SET #status = :status, status_message = :status_message",
            expression_attribute_values={
                ":status": status,
                ":status_message": status_message,
            },
            expression_attribute_names={
                "#status": "status",
            },
            response_type=Session,
            return_values="ALL_NEW",
        )
