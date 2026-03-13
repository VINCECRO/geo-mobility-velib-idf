"""
FastAPI wrapper pour l'agent Vélib.

Endpoint : POST /ask  {"question": str} → {"answer": str}

Utilisé par le module Shiny via httr2.
Variables d'environnement requises : identiques à agent.py + GROQ_API_KEY.
"""

import logging
import os
import traceback
from pathlib import Path

from fastapi import FastAPI, HTTPException

logging.basicConfig(level=logging.INFO)
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from agent import _SYSTEM_BASE, _to_groq_tools, ask
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

app = FastAPI(title="Vélib Agent API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["POST", "GET"],
    allow_headers=["*"],
)

SERVER_SCRIPT = Path(__file__).parent / "velib_mcp_server.py"


class Question(BaseModel):
    question: str


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/ask")
async def ask_endpoint(q: Question):
    if not q.question.strip():
        raise HTTPException(status_code=400, detail="Question vide.")

    server_params = StdioServerParameters(
        command="python",
        args=[str(SERVER_SCRIPT)],
        env=os.environ.copy(),
    )

    try:
        async with stdio_client(server_params) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()

                tools_result = await session.list_tools()
                groq_tools = _to_groq_tools(tools_result.tools)

                schema_result = await session.read_resource("schema://velib")
                schema_text = schema_result.contents[0].text if schema_result.contents else ""
                system_prompt = _SYSTEM_BASE.format(schema=schema_text)

                answer = await ask(q.question, session, groq_tools, system_prompt, verbose=False)

    except Exception as e:
        logging.error("ask_endpoint error:\n%s", traceback.format_exc())
        raise HTTPException(status_code=500, detail=traceback.format_exc())

    return {"answer": answer}
