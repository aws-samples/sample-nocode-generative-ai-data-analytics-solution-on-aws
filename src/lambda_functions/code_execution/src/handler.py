# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import os
import shutil
import signal
from typing import Any, cast

from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.parser import parse
from aws_lambda_powertools.utilities.typing import LambdaContext
from codeinterpreter_lib.aws_helpers.s3_helper import S3Helper
from codeinterpreter_lib.model.core import CodeExecutionLambdaInputPayload
from python_repl import PythonRepl  # type: ignore

logger = Logger()
tracer = Tracer()

python_repl = PythonRepl()


def do_imports():
    import matplotlib.pyplot  # type: ignore # noqa: F401
    import seaborn  # type: ignore # noqa: F401
    import sklearn  # type: ignore # noqa: F401
    import pandas as pd  # type: ignore # noqa: F401

    pd.set_option("display.max_columns", 50)


def __get_session_path(session_id: str) -> str:
    return f"/tmp/{session_id}/"  # nosec B108


def download_session_files(s3_helper: S3Helper, session_id: str) -> list[str]:
    os.makedirs(__get_session_path(session_id), exist_ok=True)
    s3_helper.download_session_files(session_id, __get_session_path(session_id))
    return os.listdir(__get_session_path(session_id))


def upload_and_cleanup_session_files(
    s3_helper: S3Helper, session_id: str, tmp_files_before_code_execution: list[str]
) -> list[str]:
    tmp_files_after_code_execution = os.listdir(__get_session_path(session_id))
    tmp_files_to_upload = [
        x
        for x in tmp_files_after_code_execution
        if x not in tmp_files_before_code_execution
    ]
    logger.debug(f"Uploading created files to S3: {tmp_files_to_upload}")

    for file_to_upload in tmp_files_to_upload:
        s3_helper.upload_local_file(
            session_id=session_id,
            filename=file_to_upload,
            local_filepath=os.path.join(__get_session_path(session_id), file_to_upload),
        )

    shutil.rmtree(__get_session_path(session_id))
    return tmp_files_to_upload


@logger.inject_lambda_context
@tracer.capture_lambda_handler
def lambda_handler(input_event: dict[str, Any], context: LambdaContext):
    signal.alarm(int(context.get_remaining_time_in_millis() / 1000) - 15)

    try:
        if not input_event:
            do_imports()  # do common imports now, to be faster later
            logger.info("Received empty input event, assuming warm-up call.")
            return

        event = parse(input_event, CodeExecutionLambdaInputPayload)

        logger.info("Received event", event=event)
        os.makedirs(f"/tmp/{event.session_id}/", exist_ok=True)  # nosec B108

        s3_helper = S3Helper(credentials=cast(dict, event.aws_credentials))

        # download files
        tmp_files_before_code_execution = download_session_files(
            s3_helper, event.session_id
        )
        logger.debug(f"Downloaded session files: {tmp_files_before_code_execution}")

        # run the code
        with tracer.provider.in_subsegment("## code execution"):
            response = python_repl.run(event.code, event.timeout)

        # upload generated files
        generated_files = upload_and_cleanup_session_files(
            s3_helper, event.session_id, tmp_files_before_code_execution
        )
        logger.debug(f"Uploaded new session files: {generated_files}")

        response.generated_files = generated_files
        return response.model_dump()
    finally:
        signal.alarm(0)
