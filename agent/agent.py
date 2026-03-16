"""
Vélib Agent — natural language querying of the PostGIS database via MCP.

Architecture:
    CLI / stdin  →  Agent (Groq / qwen3-32b)  →  MCP Client
                                                       ↓ stdio
                                              velib_mcp_server.py
                                                       ↓
                                                PostGIS :5432

Usage:
    python agent.py "Which stations are currently critical?"
    python agent.py          # interactive mode (REPL)

Required environment variable:
    GROQ_API_KEY   (free account: console.groq.com)
"""

import asyncio
import json
import os
import sys
from pathlib import Path

os.environ.setdefault("POSTGIS_VELIB_HOST", "localhost")

from groq import Groq
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

MODEL = "qwen/qwen3-32b"
SERVER_SCRIPT = Path(__file__).parent / "velib_mcp_server.py"

_SYSTEM_BASE = """You are a data analyst for the Vélib' bike-sharing system in Île-de-France.
You answer natural language questions by querying a PostGIS database.

Process for each question:
1. Identify the relevant tables and columns from the schema provided below.
2. Write and execute the SQL using query_velib().
3. If the query returns an error, correct and retry once.
4. Summarize the answer in natural language, citing key figures.

Important SQL rules:
- Always include LIMIT.
- The grain of fct_station_availability is (station_id, extracted_at) every 5 min —
  always aggregate before counting or averaging over a time range.
- Database timezone: Europe/Paris.

Always show the SQL used at the end of your response (```sql``` block).
Reply in the same language as the question.

{schema}
"""


# ---------------------------------------------------------------------------
# Convert MCP tools → OpenAI / Groq format
# ---------------------------------------------------------------------------

def _to_groq_tools(mcp_tools) -> list[dict]:
    return [
        {
            "type": "function",
            "function": {
                "name": t.name,
                "description": t.description or "",
                "parameters": t.inputSchema,
            },
        }
        for t in mcp_tools
    ]


# ---------------------------------------------------------------------------
# Agentic loop (one question)
# ---------------------------------------------------------------------------

async def ask(
    question: str,
    session: ClientSession,
    groq_tools: list[dict],
    system_prompt: str,
    verbose: bool = True,
) -> str:
    """Execute a question and return the final answer as text."""
    client = Groq(api_key=os.environ["GROQ_API_KEY"])

    if verbose:
        print(f"\n{'─' * 60}")
        print(f"Question: {question}")
        print('─' * 60)

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": question},
    ]
    answer = ""

    while True:
        response = client.chat.completions.create(
            model=MODEL,
            messages=messages,
            tools=groq_tools,
            tool_choice="auto",
            parallel_tool_calls=False,
            max_tokens=4096,
        )

        msg = response.choices[0].message
        messages.append(msg)

        if msg.content:
            answer = msg.content
            if verbose:
                print(msg.content)

        # Done: no tool call
        if response.choices[0].finish_reason != "tool_calls" or not msg.tool_calls:
            break

        # Execute tools via the MCP server
        for call in msg.tool_calls:
            args = json.loads(call.function.arguments)
            if verbose:
                print(f"\n  [tool] {call.function.name}({call.function.arguments[:120]}…)")

            result = await session.call_tool(call.function.name, args)
            content = result.content[0].text if result.content else "(no result)"

            if verbose:
                preview = content[:200] + "…" if len(content) > 200 else content
                print(f"  [result] {preview}")

            messages.append({
                "role": "tool",
                "tool_call_id": call.id,
                "content": content,
            })

    if verbose:
        print('─' * 60)

    return answer


# ---------------------------------------------------------------------------
# MCP session (server lifecycle)
# ---------------------------------------------------------------------------

async def run(questions: list[str]) -> None:
    server_params = StdioServerParameters(
        command="python",
        args=[str(SERVER_SCRIPT)],
        env=os.environ.copy(),  # pass all env vars to the MCP subprocess
    )

    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            # Tool discovery
            tools_result = await session.list_tools()
            groq_tools = _to_groq_tools(tools_result.tools)
            print(f"MCP server connected — {len(tools_result.tools)} tool(s): "
                  f"{[t.name for t in tools_result.tools]}")

            # Inject schema into system prompt (static resource)
            schema_result = await session.read_resource("schema://velib")
            schema_text = schema_result.contents[0].text if schema_result.contents else ""
            system_prompt = _SYSTEM_BASE.format(schema=schema_text)

            for q in questions:
                await ask(q, session, groq_tools, system_prompt)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    args = sys.argv[1:]

    if args:
        asyncio.run(run([" ".join(args)]))
    else:
        print("Vélib Agent — interactive mode (Ctrl+C to quit)")
        try:
            while True:
                q = input("\n> ").strip()
                if q:
                    asyncio.run(run([q]))
        except (KeyboardInterrupt, EOFError):
            print("\nGoodbye.")


if __name__ == "__main__":
    main()
