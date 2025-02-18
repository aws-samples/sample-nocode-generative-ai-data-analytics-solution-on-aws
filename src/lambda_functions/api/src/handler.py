# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""API Lambda for Code Interpreter."""

from typing import Any
import uuid
from decimal import Decimal

from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.event_handler import APIGatewayRestResolver
from aws_lambda_powertools.event_handler.exceptions import (
    BadRequestError,
    NotFoundError,
)
from aws_lambda_powertools.logging import correlation_paths
from aws_lambda_powertools.utilities.typing import LambdaContext
from boto3.dynamodb.conditions import Key
from codeinterpreter_lib.aws_helpers.api_middleware import (
    middleware_verify_user_session,
)
from codeinterpreter_lib.aws_helpers.ddb_helper import DDBHelper
from codeinterpreter_lib.aws_helpers.lambda_helper import LambdaHelper
from codeinterpreter_lib.aws_helpers.s3_helper import (
    S3_META_HEADER_PREFIX,
    S3_ROLE_TAG_NAME,
    S3Helper,
)
from codeinterpreter_lib.aws_helpers.util import get_user_id
from codeinterpreter_lib.model.api import FileDescription
from codeinterpreter_lib.model.core import (
    AgentServiceLambdaInputPayload,
    Message,
    Role,
    Session,
    SessionStatus,
)

tracer = Tracer()
logger = Logger()

app = APIGatewayRestResolver(strip_prefixes=["/api"])

ddb_helper = DDBHelper()
lambda_helper = LambdaHelper()
s3_helper = S3Helper()


@app.get("/sessions")
@tracer.capture_method
def get_sessions() -> list[dict[str, Any]]:
    user_id = get_user_id(app.current_event)

    sessions: list[Session] = ddb_helper.query_table(
        table=ddb_helper.sessions_table,
        key_condition_expression=Key("user_id").eq(user_id),
        response_type=Session,
    )
    return [x.api_dump() for x in sessions]


@app.get("/sessions/<session_id>")
@tracer.capture_method
def get_session(session_id: str) -> dict[str, Any]:
    user_id = get_user_id(app.current_event)

    session: Session | None = ddb_helper.get_item(
        table=ddb_helper.sessions_table,
        key={"user_id": user_id, "session_id": session_id},
        response_type=Session,
    )
    if not session:
        raise NotFoundError()

    ret_val = session.api_dump()

    if (
        app.current_event.query_string_parameters
        and "include_messages_from" in app.current_event.query_string_parameters
    ):
        from_timestamp = Decimal(
            app.current_event.get_query_string_value("include_messages_from", "0")
        )
        messages: list[Message] = ddb_helper.query_table(
            table=ddb_helper.messages_table,
            key_condition_expression=Key("session_id").eq(session_id)
            & Key("timestamp").gt(from_timestamp),
            response_type=Message,
        )
        ret_val["messages"] = [x.api_dump() for x in messages]

    return ret_val


@app.post("/sessions")
@tracer.capture_method
def post_session():
    session_id = str(uuid.uuid4())
    user_id = get_user_id(app.current_event)

    session = Session(
        user_id=user_id,
        session_id=session_id,
        status=SessionStatus.DONE,
        ttl=ddb_helper.get_ttl(),
    )

    logger.debug("Putting session item to DDB.", session=session)

    ddb_helper.put_item(table=ddb_helper.sessions_table, item=session)

    # pre-warm agent service Lambda for subsequent calls to be faster
    lambda_helper.prewarm_lambda_async(
        lambda_helper.lambda_settings.AGENT_SERVICE_FUNCTION_NAME
    )

    return session.api_dump()


@app.delete("/sessions/<session_id>")
@tracer.capture_method
def delete_session(session_id: str):
    user_id = get_user_id(app.current_event)

    response = ddb_helper.delete_item(
        table=ddb_helper.sessions_table,
        key={"user_id": user_id, "session_id": session_id},
        return_values="ALL_OLD",
    )
    if not response["Attributes"]:
        raise NotFoundError()

    return {}


@app.get(
    "/sessions/<session_id>/messages", middlewares=[middleware_verify_user_session]
)
@tracer.capture_method
def get_session_messages(session_id: str):
    from_timestamp = Decimal(app.current_event.get_query_string_value("from", "-1"))

    messages: list[Message] = ddb_helper.query_table(
        table=ddb_helper.messages_table,
        key_condition_expression=Key("session_id").eq(session_id)
        & Key("timestamp").gt(from_timestamp),
        response_type=Message,
    )

    return [x.api_dump() for x in messages]


@app.get(
    "/sessions/<session_id>/files",
    middlewares=[middleware_verify_user_session],
)
@tracer.capture_method
def get_session_files(session_id: str) -> list[FileDescription]:
    return s3_helper.list_session_files(session_id)


@app.get(
    "/sessions/<session_id>/files/upload",
    middlewares=[middleware_verify_user_session],
)
@tracer.capture_method
def get_presigned_upload_url(session_id: str) -> dict[str, Any] | None:
    user_id = get_user_id(app.current_event)
    filename = app.current_event.get_query_string_value("filename")
    if filename is None:
        raise BadRequestError("filename must be provided")

    logger.debug(
        "Creating presigned upload URL.",
        user_id=user_id,
        session_id=session_id,
        user_filename=filename,
    )

    fields = {S3_META_HEADER_PREFIX + S3_ROLE_TAG_NAME: Role.USER}
    conditions = [fields]
    return s3_helper.create_presigned_upload_url(
        session_id, filename, fields=fields, conditions=conditions
    )


@app.get(
    "/sessions/<session_id>/files/download",
    middlewares=[middleware_verify_user_session],
)
@tracer.capture_method
def get_presigned_download_url(session_id: str) -> dict[str, Any] | None:
    user_id = get_user_id(app.current_event)
    filename = app.current_event.get_query_string_value("filename")
    if filename is None:
        raise BadRequestError("filename must be provided")

    logger.debug(
        "Creating presigned download URL.",
        user_id=user_id,
        session_id=session_id,
        user_filename=filename,
    )
    return s3_helper.create_presigned_download_url(session_id, filename)


@app.post(
    "/sessions/<session_id>/messages", middlewares=[middleware_verify_user_session]
)
@tracer.capture_method
def post_session_message(session_id: str) -> dict[str, Any]:
    user_id = get_user_id(app.current_event)

    content = app.current_event.json_body.get("content")
    logger.debug(f"User posted message with {content=}")

    message = Message(
        session_id=session_id,
        role=Role.USER,
        content=content,
    )

    # post to chat history table
    # ddb_helper.put_item(table=ddb_helper.messages_table, item=message)

    # set session status pending and put status message
    session = ddb_helper.update_session(
        user_id=user_id,
        session_id=session_id,
        status=SessionStatus.PENDING,
        status_message="initializing",
    )

    # invoke code execution Lambda async
    lambda_helper.invoke_lambda_async(
        function_name=lambda_helper.lambda_settings.AGENT_SERVICE_FUNCTION_NAME,  # type: ignore
        payload=AgentServiceLambdaInputPayload(
            user_id=user_id, session_id=session_id, message=message
        ),
    )
    return session.api_dump()


@logger.inject_lambda_context(correlation_id_path=correlation_paths.API_GATEWAY_REST)
@tracer.capture_lambda_handler
def lambda_handler(event: dict[str, Any], context: LambdaContext) -> dict[str, Any]:
    return app.resolve(event, context)
