# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

from aws_lambda_powertools import Logger
from aws_lambda_powertools.event_handler import APIGatewayRestResolver, Response
from aws_lambda_powertools.event_handler.exceptions import UnauthorizedError
from aws_lambda_powertools.event_handler.middlewares import NextMiddleware
from .ddb_helper import DDBHelper
from .util import get_user_id

logger = Logger()

ddb_helper = DDBHelper()


def middleware_verify_user_session(
    app: APIGatewayRestResolver, next_middleware: NextMiddleware
) -> Response:
    session_id = app.current_event.path_parameters.get("session_id")
    user_id = get_user_id(app.current_event)

    logger.debug(
        "Verifying user is allowed to access session",
        path=app.current_event.path,
        session_id=session_id,
        user_id=user_id,
    )

    if not ddb_helper.is_user_allowed_to_access_session(user_id, session_id):
        raise UnauthorizedError("User is not allowed to access session")

    return next_middleware(app)
