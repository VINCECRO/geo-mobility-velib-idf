"""
Agent Vélib — interrogation en langage naturel de la base PostGIS via MCP.

Architecture :
    CLI / stdin  →  Agent (Groq / llama-3.3-70b)  →  MCP Client
                                                           ↓ stdio
                                                  velib_mcp_server.py
                                                           ↓
                                                    PostGIS :5432

Usage :
    python agent.py "Quelles stations sont critiques en ce moment ?"
    python agent.py          # mode interactif (REPL)

Variable d'environnement requise :
    GROQ_API_KEY   (compte gratuit : console.groq.com)
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

_SYSTEM_BASE = """Tu es un analyste données pour le système Vélib' en Île-de-France.
Tu réponds à des questions en langage naturel en interrogeant une base PostGIS.

Processus à suivre pour chaque question :
1. Identifier les tables et colonnes pertinentes dans le schéma fourni ci-dessous.
2. Écrire et exécuter le SQL avec query_velib().
3. Si la requête retourne une erreur, corriger et réessayer une fois.
4. Synthétiser la réponse en langage naturel en citant les chiffres clés.

Règles SQL importantes :
- Toujours inclure LIMIT.
- Le grain de fct_station_availability est (station_id, extracted_at) toutes les 5 min —
  toujours agréger avant de compter ou moyenner sur une plage temporelle.
- Fuseau horaire de la base : Europe/Paris.

Présente toujours le SQL utilisé à la fin de ta réponse (bloc ```sql```).
Réponds dans la même langue que la question.

{schema}
"""


# ---------------------------------------------------------------------------
# Conversion MCP tools → format OpenAI / Groq
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
# Boucle agentique (une question)
# ---------------------------------------------------------------------------

async def ask(
    question: str,
    session: ClientSession,
    groq_tools: list[dict],
    system_prompt: str,
    verbose: bool = True,
) -> str:
    """Exécute une question et retourne la réponse finale en texte."""
    client = Groq(api_key=os.environ["GROQ_API_KEY"])

    if verbose:
        print(f"\n{'─' * 60}")
        print(f"Question : {question}")
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

        # Fin : aucun appel d'outil
        if response.choices[0].finish_reason != "tool_calls" or not msg.tool_calls:
            break

        # Exécution des tools via le serveur MCP
        for call in msg.tool_calls:
            args = json.loads(call.function.arguments)
            if verbose:
                print(f"\n  [tool] {call.function.name}({call.function.arguments[:120]}…)")

            result = await session.call_tool(call.function.name, args)
            content = result.content[0].text if result.content else "(aucun résultat)"

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
# Session MCP (cycle de vie du serveur)
# ---------------------------------------------------------------------------

async def run(questions: list[str]) -> None:
    server_params = StdioServerParameters(
        command="python",
        args=[str(SERVER_SCRIPT)],
        env=os.environ.copy(),  # transmet toutes les vars au sous-processus MCP
    )

    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            # Découverte des outils
            tools_result = await session.list_tools()
            groq_tools = _to_groq_tools(tools_result.tools)
            print(f"Serveur MCP connecté — {len(tools_result.tools)} outil(s) : "
                  f"{[t.name for t in tools_result.tools]}")

            # Injection du schéma dans le system prompt (resource statique)
            schema_result = await session.read_resource("schema://velib")
            schema_text = schema_result.contents[0].text if schema_result.contents else ""
            system_prompt = _SYSTEM_BASE.format(schema=schema_text)

            for q in questions:
                await ask(q, session, groq_tools, system_prompt)


# ---------------------------------------------------------------------------
# Point d'entrée
# ---------------------------------------------------------------------------

def main() -> None:
    args = sys.argv[1:]

    if args:
        asyncio.run(run([" ".join(args)]))
    else:
        print("Agent Vélib — mode interactif (Ctrl+C pour quitter)")
        try:
            while True:
                q = input("\n> ").strip()
                if q:
                    asyncio.run(run([q]))
        except (KeyboardInterrupt, EOFError):
            print("\nAu revoir.")


if __name__ == "__main__":
    main()
