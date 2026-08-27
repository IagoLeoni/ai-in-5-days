.PHONY: help install dev-install lint format test eval eval-agent doctor env serve run web docker-build docker-run config deploy plan destroy deploy-agent-engine deploy-cloud-run tf-init tf-plan tf-apply clean check

# Detect a local virtualenv so `make` works whether or not one is activated.
PY := $(shell [ -x .venv/bin/python ] && echo .venv/bin/python || echo python3)
PIP := $(PY) -m pip

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

install: ## Install the package
	$(PIP) install -e .

dev-install: ## Install with dev and GCP extras
	$(PIP) install -e ".[dev,gcp]"

lint: ## Lint
	$(PY) -m ruff check stack_scribe tests

format: ## Auto-format
	$(PY) -m ruff format stack_scribe tests
	$(PY) -m ruff check --fix stack_scribe tests

test: ## Run unit tests
	$(PY) -m pytest tests/ -v

eval: ## Run the deterministic evaluation suite (no credentials needed)
	$(PY) -m stack_scribe.evaluation.run_eval

eval-agent: ## Run the golden-dataset evaluation against the live agent (needs credentials)
	$(PY) -m stack_scribe.evaluation.run_eval --with-agent

check: lint test eval ## Everything CI runs, locally

doctor: ## Show what is configured and what will degrade (run this first)
	$(PY) -m stack_scribe.doctor

env: ## Create .env from the template for local development
	@test -f .env && echo ".env already exists - not overwriting" \
		|| (cp .env.example .env && echo "Created .env - paste your key from https://aistudio.google.com/apikey, then run 'make doctor'")

serve: ## Serve the agent over HTTP locally (same entry point as production)
	$(PY) -m google.adk.cli api_server --host 127.0.0.1 --port 8080 .

run: ## Chat with the agent in the terminal
	$(PY) -m google.adk.cli run stack_scribe

web: ## Open the ADK dev UI (tool calls, traces, state)
	$(PY) -m google.adk.cli web .

docker-build: ## Build the container
	docker build -t stackscribe:local .

docker-run: ## Run the container locally
	docker run --rm -p 8080:8080 \
		-e GOOGLE_CLOUD_PROJECT=$(GOOGLE_CLOUD_PROJECT) \
		-v $(HOME)/.config/gcloud:/home/stackscribe/.config/gcloud:ro \
		stackscribe:local

config: ## Create deployment/config.env from the template
	@test -f deployment/config.env \
		&& echo "deployment/config.env already exists - not overwriting" \
		|| (cp deployment/config.env.example deployment/config.env \
		    && echo "Created deployment/config.env - set PROJECT_ID and INVOKER, then run 'make deploy'")

deploy: ## Provision everything and deploy the agent (edit deployment/config.env first)
	./deployment/bootstrap.sh

plan: ## Preview infrastructure changes without applying them
	PLAN_ONLY=1 ./deployment/bootstrap.sh

deploy-agent-engine: ## Deploy the agent only, to Agent Engine (infra must already exist)
	./deployment/deploy.sh agent-engine

deploy-cloud-run: ## Deploy the agent only, to Cloud Run (infra must already exist)
	./deployment/deploy.sh cloud-run

destroy: ## Tear down all provisioned infrastructure (destructive, asks first)
	@echo "This destroys StackScribe infrastructure including the session database."
	@read -p "Type the project id to confirm: " confirm; \
	. ./deployment/config.env; \
	[ "$$confirm" = "$$PROJECT_ID" ] || { echo "Aborted."; exit 1; }; \
	cd deployment/terraform && terraform destroy -var="project_id=$$PROJECT_ID"

tf-init: ## terraform init
	cd deployment/terraform && terraform init

tf-plan: ## terraform plan (set PROJECT_ID)
	cd deployment/terraform && terraform plan -var="project_id=$(PROJECT_ID)"

tf-apply: ## terraform apply (set PROJECT_ID)
	cd deployment/terraform && terraform apply -var="project_id=$(PROJECT_ID)"

clean: ## Remove build artefacts and local state
	rm -rf build dist *.egg-info .pytest_cache .ruff_cache .stackscribe
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
