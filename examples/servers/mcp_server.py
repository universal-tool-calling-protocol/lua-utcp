#!/usr/bin/env python3

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("lua-utcp-example", host="127.0.0.1", port=8093)


@mcp.tool()
def echo(message: str) -> str:
    """Echo a message."""
    return message


if __name__ == "__main__":
    mcp.run(transport="streamable-http")