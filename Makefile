# ── Variables ──────────────────────────────────────────────────────────────
DC_AIRFLOW = docker compose -f docker-compose-Airflow.yml
DC_SUPERSET     = docker compose -f docker-compose-Superset.yml
DC_SHINY     = docker compose -f docker-compose-Shiny.yml

AF_EXEC    = $(DC_AIRFLOW) exec airflow-worker airflow-worker
SUPERSET_EXEC    = $(DC_SUPERSET) exec airflow-worker airflow-worker
SHINY_EXEC     = $(DC_SHINY) exec shiny shiny

.PHONY: up-airflow up-superset up-shiny up down-all down-airflow down-superset
	down-shiny logs-airflow logs-superset logs-shiny shell-airflow shell-superset shell-shiny
	down-clean-airflow down-clean-superset down-clean-shiny down-clean-all restart-airflow restart-superset
	restart-shiny	

# ── Start ──────────────────────────────────────────────────────────────
up-airflow:
	$(DC_AIRFLOW) up -d

up-superset:
	$(DC_SUPERSET) up -d

up-shiny:
	$(DC_SHINY) up -d

up: up-airflow up-shiny  # Start Airflow & Shiny

# ── STOP ──────────────────────────────────────────────────────────────────
down-airflow:
	$(DC_AIRFLOW) down

down-superset:
	$(DC_SUPERSET) down

down-shiny:
	$(DC_SHINY) down	

down-all: # Stop Airflow & Shiny
	$(DC_AIRFLOW) down
	$(DC_SHINY) down

# ── STOP & CLEAN ──────────────────────────────────────────────────────────────────
down-clean-airflow:
	$(DC_AIRFLOW) down -v 

down-clean-superset:
	$(DC_SUPERSET) down -v

down-clean-shiny:
	$(DC_SHINY) down -v

down-clean-all: # Stop and clean Airflow & Shiny
	$(DC_AIRFLOW) down -v
	$(DC_SHINY) down -v

# ── RESTART ──────────────────────────────────────────────────────────────────
restart-airflow:
	$(DC_AIRFLOW) restart

restart-superset:
	$(DC_SUPERSET) restart

restart-shiny:
	$(DC_SHINY) restart	

restart-all: # Stop Airflow & Shiny
	$(DC_AIRFLOW) restart
	$(DC_SHINY) restart	

# ── EXECUTE ──────────────────────────────────────────────────────────────────
shell-airflow:
	$(DC_AIRFLOW) exec airflow-worker bash

shell-superset:
	$(DC_SUPERSET) exec superset bash

shell-shiny:
	$(DC_SHINY) exec shiny bash	

# ── Logs ───────────────────────────────────────────────────────────────────
logs-airflow:
	$(DC_AIRFLOW) logs -f

logs-superset:
	$(DC_SUPERSET) logs -f

logs-shiny:
	$(DC_SHINY) logs -f
