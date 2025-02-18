# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import json
import re
from streamlit.delta_generator import DeltaGenerator


def extract_tags(text, tags):
    tag_str = "|".join(tags)
    results = []
    last_end_pos = 0
    for match in re.finditer(f"<(?P<tag>{tag_str})>(?P<content>.*?)</(?P=tag)>", text):
        text_before_tag = text[last_end_pos : match.start()]
        if len(text_before_tag) > 0:
            results.append(("text", text_before_tag))
        last_end_pos = match.end()

        results.append((match.group("tag"), match.group("content")))
    text_after_tags = text[last_end_pos:]
    if len(text_after_tags) > 0:
        results.append(("text", text_after_tags))

    return results


def render_trace_message(view: DeltaGenerator, trace: str):
    trace_obj = json.loads(trace)
    inner_trace = trace_obj.get("trace", {}).get("orchestrationTrace", {})

    header = ""
    markdown_message = ""
    json_message = None

    if "type" in trace_obj:
        header = trace_obj["type"]
        for k, v in trace_obj.items():
            if k != "type":
                markdown_message += f"{k}: {v}\n\n"
    elif "rationale" in inner_trace:
        header = "Rationale"
        markdown_message = inner_trace["rationale"]["text"]
    elif "modelInvocationInput" in inner_trace:
        header = "modelInvocationInput"
        try:
            json_message = json.loads(inner_trace["modelInvocationInput"]["text"])
        except Exception as _:
            markdown_message = f"```\n{inner_trace['modelInvocationInput']['text']}```"
    elif "modelInvocationOutput" in inner_trace:
        header = "modelInvocationOutput"
        content_obj = json.loads(
            inner_trace["modelInvocationOutput"]["rawResponse"]["content"]
        )

        markdown_message = content_obj.get("content", [{}])[0].get("text")
        json_message = {
            "content": content_obj.get("content"),
            "model": content_obj.get("model"),
            "metadata": inner_trace["modelInvocationOutput"]["metadata"],
        }
    elif "invocationInput" in inner_trace:
        header = "invocationInput"
        json_message = inner_trace["invocationInput"]["actionGroupInvocationInput"]
    elif "observation" in inner_trace:
        header = "observation"
        markdown_message = inner_trace["observation"]["finalResponse"]["text"]

    markdown_text = f"### Bedrock Agent Trace: {header}"
    if markdown_message:
        markdown_text += f"\n\n{markdown_message}"
    view.markdown(markdown_text)

    if json_message:

        def clean_nones(value):
            if isinstance(value, list):
                return [clean_nones(x) for x in value if x is not None]
            elif isinstance(value, dict):
                return {
                    key: clean_nones(val)
                    for key, val in value.items()
                    if val is not None
                }
            else:
                return value

        view.code(
            json.dumps(clean_nones(json_message), indent=2),
            language="json",
            wrap_lines=True,
        )


def render_tool_message(view: DeltaGenerator, content: str):
    content_obj = json.loads(content)
    view.markdown("## Python Tool")
    view.code(content_obj.get("python_code"), language="python", wrap_lines=True)

    output = content_obj.get("output", {})

    if output.get("execution_time", -1) > 0:
        view.text(
            f"Code execution time: {output.get('execution_time'):.2f} seconds\n\n"
        )
    if output.get("stdout"):
        view.markdown(f"#### Output\n```\n{output.get('stdout')}\n```\n\n")
    if output.get("stderr"):
        view.markdown(f"#### Errors\n```\n{output.get('stderr')}\n```\n\n")
    if output.get("generated_files"):
        view.markdown(
            f"#### Generated files\n```\n{'\n'.join(output.get('generated_files', []))}\n```"
        )
