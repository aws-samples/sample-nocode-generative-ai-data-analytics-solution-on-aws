# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

from aws_lambda_powertools.utilities.typing import LambdaContext
from aws_lambda_powertools import Tracer, Logger

from aws_lambda_powertools.utilities.batch import (
    BatchProcessor,
    EventType,
    process_partial_response,
)
from aws_lambda_powertools.utilities.data_classes.dynamo_db_stream_event import (
    DynamoDBRecord,
    DynamoDBRecordEventName,
)

from codeinterpreter_lib.aws_helpers.ddb_helper import DDBHelper
from codeinterpreter_lib.aws_helpers.s3_helper import S3Helper

processor = BatchProcessor(event_type=EventType.DynamoDBStreams)
logger = Logger()
tracer = Tracer()

ddb_helper = DDBHelper()
s3_helper = S3Helper()


@tracer.capture_method
def record_handler(record: DynamoDBRecord):
    if (
        record.dynamodb
        and record.event_name == DynamoDBRecordEventName.REMOVE
        and "session_id" in record.dynamodb.keys
    ):
        session_id = record.dynamodb.keys.get("session_id", "")

        logger.info(f"Cleaning up session with ID {session_id}.")

        s3_helper.clear_session_files(session_id)
        ddb_helper.clear_session_messages(session_id)


@logger.inject_lambda_context
@tracer.capture_lambda_handler
def lambda_handler(event, context: LambdaContext):
    return process_partial_response(
        event=event, record_handler=record_handler, processor=processor, context=context
    )
