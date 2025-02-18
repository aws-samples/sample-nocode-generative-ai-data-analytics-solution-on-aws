# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

from contextlib import redirect_stderr, redirect_stdout
import io
from multiprocessing import Pipe, Process
from multiprocessing.connection import Connection
import os
import time
from typing import Any
import uuid
import tempfile
from aws_lambda_powertools import Logger

from codeinterpreter_lib.model.core import CodeExecutionLambdaResponsePayload

logger = Logger()


class PythonRepl:
    def __get_code_execution_environ(self) -> dict[str, str]:
        return {"MPLCONFIGDIR": tempfile.mkdtemp()}

    def __code_executor(
        self, command: str, connection: Connection | None = None
    ) -> tuple[str, str, float]:
        old_os_environ = os.environ.copy()
        try:
            os.environ = self.__get_code_execution_environ()  # type: ignore
            with (
                redirect_stdout(io.StringIO()) as stdout_io,
                redirect_stderr(io.StringIO()) as stderr_io,
            ):
                start_time = time.time()
                ast = compile(command, f"{uuid.uuid4()}.py", "exec")
                variables: dict[str, Any] = {}
                exec(ast, variables, variables)  # nosemgrep: exec-detected # nosec B102
                execution_time = time.time() - start_time
                logger.info(f"Finished code execution after {execution_time:.5f}s.")

            stdout_str = stdout_io.getvalue()
            stderr_str = stderr_io.getvalue()

            ret_val = (stdout_str, stderr_str, execution_time)

            if connection:
                connection.send(ret_val)
                connection.close()

            return ret_val

        except Exception as e:
            import traceback

            logger.warning(f"Exception in code_executor ==> {e}", exc_info=True)
            ret_val = ("", "\n".join(traceback.format_exception(e, limit=3)), -1)
            if connection:
                connection.send(ret_val)
                connection.close()

            return ret_val

        finally:
            os.environ = old_os_environ  # type: ignore

    def run(
        self, command: str, timeout: int | None = None
    ) -> CodeExecutionLambdaResponsePayload:
        """Run command with own globals/locals and returns anything printed.
        Timeout after the specified number of seconds."""
        logger.debug("PYTON_TOOL RUN method called")
        parent_connection, child_connection = Pipe()

        result: tuple[str, str, float]
        # Only use multiprocessing if we are enforcing a timeout
        if timeout is not None:
            logger.debug(f"Creating process with command ==> {command}")
            # create a Process
            process = Process(
                target=self.__code_executor, args=(command, child_connection)
            )

            # start it
            logger.info(f"Starting code executor module with {timeout=}secs")
            process.start()

            # wait for the process to finish or kill it after timeout seconds
            process.join(timeout)

            if process.is_alive():
                process.terminate()
                return CodeExecutionLambdaResponsePayload(
                    stdout="",
                    stderr="Execution timed out",
                    execution_time=-1,
                    generated_files=[],
                )
        else:
            # running without multiprocessing
            result = self.__code_executor(command)
            return CodeExecutionLambdaResponsePayload(
                stdout=result[0],
                stderr=result[1],
                execution_time=result[2],
                generated_files=[],
            )

        # get the result from the worker function
        result = parent_connection.recv()
        logger.debug("Received result from parent connection", result=result)

        return CodeExecutionLambdaResponsePayload(
            stdout=result[0],
            stderr=result[1],
            execution_time=result[2],
            generated_files=[],
        )
