COMPOSE_DEV  = docker compose -f docker-compose.yml -f docker-compose.dev.yml
COMPOSE_PROD = docker compose -f docker-compose.yml -f docker-compose.prod.yml
COMPOSE     ?= $(COMPOSE_DEV)
API_URL     ?= http://localhost:8000

.PHONY: help env dev-up dev-down prod-up prod-down api-health logs sync-all sync-gfs sync-enso sync-alerts sync-radar resumen install demo run test

help: ## Lista de comandos
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "  make %-12s %s\n", $$1, $$2}'

env: ## Crea .env con una clave aleatoria (si no existe)
	@test -f .env || (sed "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$$(python3 -c 'import secrets; print(secrets.token_hex(16))')/" .env.example > .env && echo ".env creado")

dev-up: env ## Levanta API + PostgreSQL en modo desarrollo (http://localhost:8000)
	$(COMPOSE_DEV) up -d --build

dev-down: ## Detiene el entorno de desarrollo
	$(COMPOSE_DEV) down

prod-up: env ## Producción con Nginx (requiere secrets/db_password.txt y ARGWX_ADMIN_TOKEN)
	@test -f secrets/db_password.txt || (echo "Falta secrets/db_password.txt" && exit 1)
	$(COMPOSE_PROD) up -d --build

prod-down: ## Detiene producción
	$(COMPOSE_PROD) down

api-health: ## Estado de la API
	@curl -fsS $(API_URL)/health && echo

logs: ## Logs de la API
	$(COMPOSE) logs -f api

sync-all: ## Sincroniza todas las fuentes
	$(COMPOSE) exec api python -m app.cli sync all

sync-gfs: ## Sincroniza modelos (GFS + ICON + ECMWF + GEM + UKMO)
	$(COMPOSE) exec api python -m app.cli sync models

sync-enso: ## Sincroniza ENSO (NOAA CPC)
	$(COMPOSE) exec api python -m app.cli sync enso

sync-alerts: ## Sincroniza alertas oficiales del SMN
	$(COMPOSE) exec api python -m app.cli sync smn

sync-radar: ## Radar (fuera del MVP)
	@echo "Radar: la ingesta no está en el MVP. Para estimar llegadas usar POST /api/v1/radar/arrival-time."

resumen: ## Resumen de alertas en consola
	$(COMPOSE) exec api python -m app.cli resumen

install: ## Sin Docker: instala dependencias
	python3 -m pip install -r requirements-dev.txt

demo: ## Sin Docker: API con escenario SIMULADO (no necesita internet)
	ARGWX_DATA_MODE=demo python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000

run: ## Sin Docker: API con datos reales (si fallan, cae a simulado y lo avisa)
	python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

test: ## Tests
	python3 -m pytest -q
