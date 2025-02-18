# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import socket
from io import BytesIO

import plotly
import streamlit as st
from streamlit.logger import get_logger
from api import Message, SessionManager  # type: ignore
from util import extract_tags, render_tool_message, render_trace_message  # type: ignore

logger = get_logger(__name__)


LOGO_SVG = (
    "https://upload.wikimedia.org/wikipedia/commons/9/93/Amazon_Web_Services_Logo.svg"
)
PAGE_TITLE = "Analytics & ML Assistant"

st.set_page_config(layout="wide", page_icon=":material/memory:", page_title=PAGE_TITLE)
st.title(PAGE_TITLE)
# st.set_option("client.toolbarMode", "minimal")

################
# session state
################
if "session_manager" not in st.session_state:
    # for demo purposes use the hostname as the user_id
    user_id = socket.gethostname()
    st.session_state.session_manager = SessionManager(user_id=user_id)
    st.session_state.messages = []
    st.session_state.processed_uploads = []
    st.session_state.session_pending = False


################
# Sidebar with file upload and reset button
################
st.logo(LOGO_SVG)
with st.sidebar:
    st.header("File upload", divider=True)
    if uploaded_file := st.file_uploader("Upload session files"):
        if uploaded_file.name not in st.session_state.processed_uploads:
            st.session_state.session_manager.upload_file(
                filename=uploaded_file.name,
                filedata=BytesIO(uploaded_file.getvalue()).read(),
            )

            st.session_state.processed_uploads.append(uploaded_file.name)

    st.header("Settings", divider=True)
    show_internal = st.toggle("Expand Trace blocks", value=True)
    st.caption(
        "Trace are thoughts and observations from the assistant that provide additional context or information."
    )

    show_trace_messages = st.checkbox("Show trace messages", value=False)
    show_tool_messages = st.checkbox("Show tool messages", value=False)

    st.caption(f"Session ID: {st.session_state.session_manager.session_id}")


def render_message(view, msg: Message):
    if msg.internal:
        view.caption("This is a trace message.")
    content = msg.content

    parsed_content = extract_tags(content, ["plotly", "md", "png"])
    if len(parsed_content) == 0 or msg.internal:
        if msg.role == "trace":
            render_trace_message(view, content)
        elif msg.role == "tool":
            render_tool_message(view, content)
        else:
            view.markdown(content)
    else:
        for tag, tag_content in parsed_content:
            if tag == "text":
                view.markdown(tag_content)
            elif tag == "md":
                try:
                    view.markdown(
                        st.session_state.session_manager.download_file(
                            tag_content
                        ).decode("utf-8")
                    )
                except Exception as e:
                    st.text(f"Unable to load file {tag_content}: {repr(e)}")
            elif tag == "plotly":
                try:
                    data = st.session_state.session_manager.download_file(
                        tag_content
                    ).decode("utf-8")
                    fig = plotly.io.from_json(data)
                    view.plotly_chart(fig)
                except Exception:
                    st.text(f"Unable to load file {tag_content}")
            elif tag == "png":
                with st.spinner("Downloading..."):
                    try:
                        url = st.session_state.session_manager.download_file_url(
                            tag_content
                        )
                        view.image(
                            url,
                        )
                    except Exception as e:
                        logger.exception(f"Unable to load file: {repr(e)}")
                        st.text(f"Unable to load file {tag_content}")


################
# Messages
################
base_view_is_expander = False
for msg in st.session_state.session_manager.get_messages():
    if (msg.role == "tool" and not show_tool_messages) or (
        msg.role == "trace" and not show_trace_messages
    ):
        continue

    if not msg.internal:
        base_view = st
        base_view_is_expander = False
    elif msg.internal and not base_view_is_expander:
        base_view = st.expander(":grey[Trace]", expanded=show_internal)  # type: ignore
        base_view_is_expander = True

    view = base_view.chat_message("user" if msg.role == "user" else "assistant")  # type: ignore
    render_message(view, msg)

################
# Chat input
################
st.session_state.status_view = st.status(
    f"Assistant is {st.session_state.session_manager.assistant_status}",
    state=(
        "complete"
        if st.session_state.session_manager.assistant_status == "ready"
        else "running"
    ),
)

if st.session_state.session_manager.error:
    st.error(st.session_state.session_manager.error)
    st.error("Please reset the session")

if input_query := st.chat_input("User:"):
    logger.info("User: " + input_query)
    st.session_state.status_view.update(
        label="Connecting to assistant...", state="running"
    )
    st.session_state.session_manager.post_message(input_query)
    st.session_state.session_pending = True

if st.session_state.session_pending:
    st.session_state.session_pending = (
        st.session_state.session_manager.wait_for_new_messages()
    )
    st.rerun()
