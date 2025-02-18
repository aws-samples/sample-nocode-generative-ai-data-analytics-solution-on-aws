# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

from functools import partial
import json
import time
from typing import Any

import boto3

from codeinterpreter_lib.aws_helpers.s3_helper import S3Helper
from codeinterpreter_lib.aws_helpers.settings import BedrockSettings
from codeinterpreter_lib.model.core import (
    Message,
    SessionStatus,
    Role,
)

from connectors.dynamo_message_storage import DynamoDBMessageStorage  # type: ignore
from aws_lambda_powertools import Logger, Tracer


from .tools.python_tool import LambdaPythonREPL


logger = Logger()
tracer = Tracer()

s3_helper = S3Helper()


class BedrockAgent:
    def __init__(
        self, session_id: str, message_storage: DynamoDBMessageStorage
    ) -> None:
        self.bedrock_settings = BedrockSettings()  # type: ignore

        self.client = boto3.client(
            service_name="bedrock-agent-runtime",
            region_name=self.bedrock_settings.AWS_REGION,
        )

        self.message_storage = message_storage
        self.session_id = session_id
        self.session_file_path = f"/tmp/{self.session_id}"  # nosec B108
        self.start_model_invocation_time = -1

        self.python_repl = LambdaPythonREPL(session_id=session_id)

        self.session_state: dict[str, Any] = {}

        self.invoke_agent = partial(
            self.client.invoke_agent,
            agentId=self.bedrock_settings.AGENT_ID,
            agentAliasId=self.bedrock_settings.AGENT_ALIAS,
            sessionId=self.session_id,
            enableTrace=True,
        )

        self.message_storage.load_messages()

    def run(self, user_message: Message) -> None:
        """
        Run the agent with the given input message.
        """

        logger.info("Starting new run", user_message=user_message)

        self.reload_user_files()

        if conversation_history := self.message_storage.get_conversation_history():
            self.session_state["conversationHistory"] = {
                "messages": conversation_history
            }

        self.message_storage.append_message(user_message)

        loop_run = 0
        start_time = time.time()
        received_final_answer = False
        while not received_final_answer:
            self.message_storage.set_session_status("thinking")
            if loop_run >= 10:
                raise Exception("Too many loops")
            loop_run += 1

            logger.debug(
                "Invoking agent",
                session_state=self.session_state,
                input_text=user_message.content,
            )
            try:
                response = self.invoke_agent(
                    sessionState=self.session_state,  # type: ignore
                    inputText=str(user_message.content),
                )
                # for subsequent runs the state should be cleared
                self._clear_session_state()

                for event in response["completion"]:
                    if "chunk" in event:
                        final_answer = event["chunk"].get("bytes", b"").decode("utf8")
                        logger.info(f"Agent provided final answer: {final_answer}")

                        # store overall stats
                        elapsed_seconds = time.time() - start_time
                        self._store_text_message(
                            Role.TRACE,
                            json.dumps(
                                {
                                    "type": "Overall Stats",
                                    "execution_time": elapsed_seconds,
                                    "agent_invocations": loop_run,
                                }
                            ),
                        )
                        self._store_text_message(Role.ASSISTANT, final_answer)
                        received_final_answer = True
                    elif "trace" in event:
                        self._store_text_message(Role.TRACE, json.dumps(event["trace"]))

                    elif "returnControl" in event:
                        self._handle_return_control(event["returnControl"])
                    else:
                        raise Exception("unexpected event.", event)

            except Exception as e:
                logger.exception(  # nosemgrep: logging-error-without-handling
                    "Error in reading agent response"
                )
                raise e

        self.message_storage.set_session_status(status=SessionStatus.DONE)

    @tracer.capture_method
    def _handle_return_control(self, return_control) -> None:
        logger.info("Agent returned control", return_control=return_control)
        self.message_storage.set_session_status("running code")

        self.session_state["invocationId"] = return_control["invocationId"]

        for invocation_input in return_control["invocationInputs"]:
            function_to_call = invocation_input["functionInvocationInput"]["function"]
            output = None
            if function_to_call == "python_repl":
                python_code = None
                for param in invocation_input["functionInvocationInput"]["parameters"]:
                    if param["name"] == "python_code":
                        python_code = param["value"]
                if python_code:
                    python_code = python_code.replace(
                        "<##scratchpad_folder##>", self.session_file_path
                    )

                    # run the code
                    output = self.python_repl.run(python_code, timeout=120)
                    logger.info("Python REPL provided output", output=output)

                    self._store_text_message(
                        Role.TOOL,
                        json.dumps(
                            {"python_code": python_code, "output": output.model_dump()}
                        ),
                    )
                    # self._store_text_message(
                    #     Role.TOOL, f"#### Tool python_repl\n{tool_message}"
                    # )

                    self.session_state.setdefault(
                        "returnControlInvocationResults", []
                    ).append(
                        {
                            "functionResult": {
                                "actionGroup": invocation_input[
                                    "functionInvocationInput"
                                ]["actionGroup"],
                                "function": invocation_input["functionInvocationInput"][
                                    "function"
                                ],
                                "responseBody": {
                                    "TEXT": {
                                        "body": output.model_dump_json(
                                            include=set(
                                                ["stdout", "stderr", "generated_files"]
                                            )
                                        )
                                    }
                                },
                                #'responseState': 'REPROMPT' if output.stderr else None
                            }
                        }
                    )

            else:
                raise Exception(f"Unknown function to call: {function_to_call}")

    @tracer.capture_method
    def reload_user_files(self) -> None:
        user_files = s3_helper.list_session_files(self.session_id, user_only=True)

        if user_files:
            self.session_state["promptSessionAttributes"] = {
                "User file uploads": ", ".join(
                    [f"<##scratchpad_folder##>/{f.filename}" for f in user_files]
                ),
            }

            # load small image files into the context
            for user_file in user_files:
                if (
                    user_file.filename.lower().endswith(
                        (".png", ".jpg", ".jpeg", ".gif", ".bmp")
                    )
                    and user_file.size < 500 * 1024
                ):
                    # self.message_storage.append_image_message(user_file.filename)
                    self.session_state.setdefault("files", []).append(
                        {
                            "name": user_file.filename,
                            "useCase": "CHAT",
                            "source": {
                                "sourceType": "S3",
                                "s3Location": {"uri": user_file.s3_location},
                            },
                        }
                    )
        else:
            self.session_state.pop("promptSessionAttributes", None)

    def _clear_session_state(self) -> None:
        self.session_state.pop("invocationId", None)
        self.session_state.pop("returnControlInvocationResults", None)
        self.session_state.pop("conversationHistory", None)

    def _store_text_message(self, role: Role, content: str) -> Message:
        message = Message(session_id=self.session_id, role=role, content=content)
        self.message_storage.append_message(message)
        return message
