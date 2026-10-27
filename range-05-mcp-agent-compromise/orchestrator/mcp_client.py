"""
range-05-mcp-agent-compromise - raw MCP client for direct reconnaissance.

Talks to the MCP server directly, with no LLM in the loop - the equivalent
of range-04's raw `aws` CLI enumeration before ever touching the Bedrock
assistant. Use this to list tools, list/read tickets, and plant your own
ticket yourself, before ever asking the agent to do anything. agent_loop.py
is for the step that actually needs a model deciding to call tools on your
behalf (getting the agent to act on an injected instruction); this script
is for everything before that.

Usage:
    python mcp_client.py list-tools
    python mcp_client.py call list_tickets
    python mcp_client.py call get_ticket_status '{"ticket_id": "TICKET-0999"}'
    python mcp_client.py call submit_ticket '{"subject": "...", "body": "..."}'

Required environment variable:
    MCP_SERVER_URL   mcp_server_url output from ../terraform (once applied),
                      or http://127.0.0.1:<port>/mcp for local development
                      against `MCP_TRANSPORT=streamable-http python server.py`.

Auth: none. This range's MCP server has no caller-identity check at all
(see export_user_directory in ../mcp-server/server.py) - this script
exercises that directly, same as anyone who can reach the Container App's
restricted ingress (see ../terraform/access.tf).
"""

from __future__ import annotations

import asyncio
import json
import os
import sys

from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client


def _require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


def _print_result(result) -> None:
    for block in result.content:
        if hasattr(block, "text"):
            print(block.text)
    if result.is_error:
        raise SystemExit(1)


async def list_tools() -> None:
    mcp_server_url = _require_env("MCP_SERVER_URL")
    async with streamable_http_client(mcp_server_url) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            discovered = await session.list_tools()
            for tool in discovered.tools:
                print(f"{tool.name}: {tool.description}")


async def call_tool(name: str, args: dict) -> None:
    mcp_server_url = _require_env("MCP_SERVER_URL")
    async with streamable_http_client(mcp_server_url) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            result = await session.call_tool(name, args)
            _print_result(result)


def main() -> None:
    usage = f"Usage: python {sys.argv[0]} list-tools | call <tool_name> [json_args]"
    if len(sys.argv) < 2:
        raise SystemExit(usage)

    command = sys.argv[1]
    if command == "list-tools":
        asyncio.run(list_tools())
    elif command == "call":
        if len(sys.argv) < 3:
            raise SystemExit(usage)
        tool_name = sys.argv[2]
        args = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
        asyncio.run(call_tool(tool_name, args))
    else:
        raise SystemExit(usage)


if __name__ == "__main__":
    main()
