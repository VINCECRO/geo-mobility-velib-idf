# ── Variables ──────────────────────────────────────────────────────────────
DC_AIRFLOW  = docker compose -f docker-compose-Airflow.yml
DC_SUPERSET = docker compose -f docker-compose-Superset.yml
DC_SHINY    = docker compose -f docker-compose-Shiny.yml
DC_AGENT    = docker compose -f docker-compose-Agent.yml

.PHONY: up-airflow up-superset up-shiny up-agent up \
	down-airflow down-superset down-shiny down-agent down-all \
	down-clean-airflow down-clean-superset down-clean-shiny down-clean-agent down-clean-all \
	restart-airflow restart-superset restart-shiny restart-agent restart-all \
	shell-airflow shell-postgis shell-superset shell-shiny shell-agent \
	logs-airflow logs-superset logs-shiny logs-agent

# ── Start ──────────────────────────────────────────────────────────────────
up-airflow:
	$(DC_AIRFLOW) up -d

up-superset:
	$(DC_SUPERSET) up -d

up-shiny:
	$(DC_SHINY) up -d

up-agent:
	$(DC_AGENT) up -d --build

up: up-airflow up-shiny  # Start Airflow & Shiny (stack principale)

# ── Stop ──────────────────────────────────────────────────────────────────
down-airflow:
	$(DC_AIRFLOW) down

down-superset:
	$(DC_SUPERSET) down

down-shiny:
	$(DC_SHINY) down

down-agent:
	$(DC_AGENT) down

down-all:
	$(DC_AIRFLOW) down
	$(DC_SHINY) down
	$(DC_AGENT) down

# ── Stop & clean volumes ───────────────────────────────────────────────────
down-clean-airflow:
	$(DC_AIRFLOW) down -v

down-clean-superset:
	$(DC_SUPERSET) down -v

down-clean-shiny:
	$(DC_SHINY) down -v

down-clean-agent:
	$(DC_AGENT) down -v

down-clean-all:
	$(DC_AIRFLOW) down -v
	$(DC_SHINY) down -v
	$(DC_AGENT) down -v

# ── Restart ────────────────────────────────────────────────────────────────
restart-airflow:
	$(DC_AIRFLOW) restart

restart-superset:
	$(DC_SUPERSET) restart

restart-shiny:
	$(DC_SHINY) restart

restart-agent:
	$(DC_AGENT) restart

restart-all:
	$(DC_AIRFLOW) restart
	$(DC_SHINY) restart
	$(DC_AGENT) restart

# ── Shell ──────────────────────────────────────────────────────────────────
shell-airflow:
	$(DC_AIRFLOW) exec airflow-worker bash

shell-postgis:
	$(DC_AIRFLOW) exec postgres-velib bash

shell-superset:
	$(DC_SUPERSET) exec superset bash

shell-shiny:
	$(DC_SHINY) exec shiny bash

shell-agent:
	$(DC_AGENT) exec agent-api bash

# ── Logs ───────────────────────────────────────────────────────────────────
logs-airflow:
	$(DC_AIRFLOW) logs -f

logs-superset:
	$(DC_SUPERSET) logs -f

logs-shiny:
	$(DC_SHINY) logs -f

logs-agent:
	$(DC_AGENT) logs -f
