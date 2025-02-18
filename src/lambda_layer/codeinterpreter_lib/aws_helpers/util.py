# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

from aws_lambda_powertools.utilities.data_classes import APIGatewayProxyEvent
from aws_lambda_powertools.logging import Logger
from aws_lambda_powertools.event_handler.exceptions import UnauthorizedError


logger = Logger()

USER_ID_HEADER_NAME = "X-Code-Interpreter-User-Id"


def get_user_id(current_event: APIGatewayProxyEvent):
    try:
        return current_event.headers[USER_ID_HEADER_NAME]
        # return current_event.request_context.authorizer.principal_id
    except KeyError:
        raise UnauthorizedError("No user_id found in request")
