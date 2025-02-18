# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

from typing import Any

from agent.bedrock_agent import BedrockAgent  # type: ignore
from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.parser import parse
from aws_lambda_powertools.utilities.typing import LambdaContext
from codeinterpreter_lib.aws_helpers.ddb_helper import DDBHelper
from codeinterpreter_lib.aws_helpers.lambda_helper import LambdaHelper
from codeinterpreter_lib.aws_helpers.s3_helper import S3Helper
from codeinterpreter_lib.model.core import (
    AgentServiceLambdaInputPayload,
    Message,
    Role,
    SessionStatus,
)
from connectors.dynamo_message_storage import DynamoDBMessageStorage  # type: ignore

ddb_helper = DDBHelper()
s3_helper = S3Helper()
lambda_helper = LambdaHelper()

# pre-warm code execution Lambda during own init for subsequent calls to be faster
lambda_helper.prewarm_lambda_async(
    lambda_helper.lambda_settings.CODE_EXECUTION_FUNCTION_NAME  # type: ignore
)

logger = Logger()
tracer = Tracer()


@logger.inject_lambda_context
@tracer.capture_lambda_handler
def lambda_handler(input_event: dict[str, Any], context: LambdaContext):
    if not input_event:
        logger.info("Received empty input event, assuming warm-up call.")
        return

    event = parse(input_event, AgentServiceLambdaInputPayload)

    try:
        message_storage = DynamoDBMessageStorage(
            session_id=event.session_id,
            user_id=event.user_id,
        )

        agent_executor = BedrockAgent(
            session_id=event.session_id,
            message_storage=message_storage,
        )
        agent_executor.run(event.message)

        return {"status": "success"}
    except Exception as e:
        logger.exception(  # nosemgrep: logging-error-without-handling
            "Error in agent service lambda"
        )
        ddb_helper.update_session(
            user_id=event.user_id,
            session_id=event.session_id,
            status=SessionStatus.ERROR,
            status_message=f"Error in agent service: {str(e)}",
        )
        raise e


class MockLambdaContext(LambdaContext):
    def __init__(self) -> None:
        self._function_name = "test-fn"
        self._memory_limit_in_mb = 128
        self._invoked_function_arn = (
            "arn:aws:lambda:us-east-1:12345678:function:test-fn"
        )
        self._aws_request_id = "52fdfc07-2182-154f-163f-5f0f9a621d72"


if __name__ == "__main__":
    session_id = "fac50fcc-baa8-4bb8-9ba1-d376e47d1d8b"
    import uuid

    session_id = str(uuid.uuid4())
    data = AgentServiceLambdaInputPayload(
        session_id=session_id,
        user_id="FOO",
        message=Message(
            session_id=session_id,
            role=Role.USER,
            content="Plot some random data",
        ),
    )
    lambda_handler(data, MockLambdaContext())
    logger.info("Finished interaction")
