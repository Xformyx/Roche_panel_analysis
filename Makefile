.PHONY: build build-analysis build-web up down restart logs status clean rebuild help save test \
        keygen license prod-up prod-down prod-logs prod-save

help:
	@echo "Roche_nxt - Nextflow ctDNA Analysis Pipeline"
	@echo "============================================="
	@echo "make build          - Build all Docker images"
	@echo "make build-analysis - Build analysis image only"
	@echo "make build-web      - Build web UI image only"
	@echo "make up             - Start Web UI"
	@echo "make down           - Stop Web UI"
	@echo "make restart        - Restart Web UI"
	@echo "make logs           - View Web UI logs"
	@echo "make status         - Check status"
	@echo "make rebuild        - Full rebuild (no cache)"
	@echo "make clean          - Remove images"
	@echo "make save           - Save images for offline deployment"
	@echo "make test           - Run test pipeline (dry-run)"
	@echo ""
	@echo "---- Licensing ----"
	@echo "make keygen         - Generate new Ed25519 signing keypair (run ONCE)"
	@echo "make license CUSTOMER=Name EXPIRES=YYYY-MM-DD FEATURES=longitudinal,igv,hg19_view"
	@echo "                    - Issue a signed license.json (writes to deploy/licenses/)"
	@echo ""
	@echo "---- Production (customer) deployment ----"
	@echo "make prod-up        - Start using docker-compose.prod.yml (license required)"
	@echo "make prod-down      - Stop the production stack"
	@echo "make prod-logs      - Tail logs of the production container"
	@echo "make prod-save      - Package image + prod compose into deploy/ for air-gap delivery"
	@echo ""
	@echo "Web UI: http://localhost:$${WEB_PORT:-8080}"

build: build-analysis build-web
	@echo "All images built!"

build-analysis:
	@echo "Building analysis image (roche_nxt_analysis:latest)..."
	docker build -t roche_nxt_analysis:latest -f containers/Dockerfile.all .
	@echo "Analysis image built!"

build-web:
	@echo "Building Web UI image (roche_nxt_web:latest)..."
	docker build -t roche_nxt_web:latest -f web_ui/Dockerfile web_ui/
	@echo "Web UI image built!"

up:
	docker-compose up -d
	@echo "Web UI running at http://localhost:$$(grep WEB_PORT .env 2>/dev/null | cut -d= -f2 || echo 8080)"

down:
	docker-compose down

restart:
	docker-compose restart

logs:
	docker-compose logs -f roche-nxt-web

status:
	docker-compose ps
	@echo ""
	@echo "Nextflow runs:"
	@ps aux | grep '[n]extflow' | head -10 || echo "  No active Nextflow runs"

rebuild:
	@echo "Rebuilding from scratch..."
	docker-compose down
	docker rmi roche_nxt_web:latest 2>/dev/null || true
	docker rmi roche_nxt_analysis:latest 2>/dev/null || true
	docker build --no-cache -t roche_nxt_analysis:latest -f containers/Dockerfile.all .
	docker build --no-cache -t roche_nxt_web:latest -f web_ui/Dockerfile web_ui/
	docker-compose up -d
	@echo "Rebuild complete!"

clean:
	docker-compose down
	docker rmi roche_nxt_web:latest 2>/dev/null || true
	docker rmi roche_nxt_analysis:latest 2>/dev/null || true

save:
	@mkdir -p deploy/images
	@echo "Saving roche_nxt_analysis:latest..."
	docker save roche_nxt_analysis:latest | gzip > deploy/images/roche_nxt_analysis.tar.gz
	@echo "  -> $$(ls -lh deploy/images/roche_nxt_analysis.tar.gz | awk '{print $$5}')"
	@echo "Saving roche_nxt_web:latest..."
	docker save roche_nxt_web:latest | gzip > deploy/images/roche_nxt_web.tar.gz
	@echo "  -> $$(ls -lh deploy/images/roche_nxt_web.tar.gz | awk '{print $$5}')"
	@echo ""
	@echo "Images saved to deploy/images/"
	@ls -lh deploy/images/

test:
	@echo "Running dry-run test..."
	nextflow run main.nf -profile docker -preview --input test/samplesheet.csv

# ---------------------------------------------------------------------------
# Licensing
# ---------------------------------------------------------------------------
KEYS_DIR ?= $(HOME)/.roche_nxt_keys

keygen:
	@mkdir -p $(KEYS_DIR)
	@docker run --rm --user "$$(id -u):$$(id -g)" \
	    -v $(KEYS_DIR):/keys \
	    -v $(PWD):/roche_nxt \
	    roche_nxt_web:latest \
	    python /roche_nxt/tools/keygen.py \
	        --out-dir /keys \
	        --bake-into /roche_nxt/web_ui/_vendor_keys/license_pubkey.b64
	@echo ""
	@echo "Keypair ready. Back up $(KEYS_DIR)/license_signing_key.b64 OFFLINE."
	@echo "Remember to rebuild the web image so it bakes in the new public key:"
	@echo "    make build-web"

# make license CUSTOMER="ABC Hospital" EXPIRES=2027-04-20 FEATURES=longitudinal,igv,hg19_view
#   - Set EXPIRES=never (or leave unset together with NO_EXPIRY=1) for a
#     perpetual license with no expiry date.
license:
	@test -n "$(CUSTOMER)"  || (echo "ERROR: CUSTOMER is required";  exit 1)
	@test -n "$(FEATURES)"  || (echo "ERROR: FEATURES is required";  exit 1)
	@if [ -z "$(EXPIRES)" ] && [ -z "$(NO_EXPIRY)" ]; then \
	    echo "ERROR: either EXPIRES=YYYY-MM-DD or NO_EXPIRY=1 is required"; exit 1; \
	fi
	@mkdir -p deploy/licenses
	@safe_name=$$(echo "$(CUSTOMER)" | tr 'A-Z ' 'a-z_' | tr -cd '[:alnum:]_-'); \
	if [ "$(EXPIRES)" = "never" ] || [ -n "$(NO_EXPIRY)" ]; then \
	    expiry_arg="--no-expiry"; \
	else \
	    expiry_arg="--expires $(EXPIRES)"; \
	fi; \
	docker run --rm --user "$$(id -u):$$(id -g)" \
	    -v $(KEYS_DIR):/keys:ro \
	    -v $(PWD):/roche_nxt \
	    roche_nxt_web:latest \
	    python /roche_nxt/tools/issue_license.py \
	        --customer "$(CUSTOMER)" \
	        $$expiry_arg \
	        --features "$(FEATURES)" \
	        --private-key /keys/license_signing_key.b64 \
	        --out /roche_nxt/deploy/licenses/$${safe_name}.json; \
	echo ""; \
	echo "License ready: deploy/licenses/$${safe_name}.json"

# ---------------------------------------------------------------------------
# Production deployment (customer side)
# ---------------------------------------------------------------------------
PROD_COMPOSE := -f docker-compose.prod.yml

prod-up:
	docker compose $(PROD_COMPOSE) up -d
	@echo "Production stack started with signed-license enforcement."

prod-down:
	docker compose $(PROD_COMPOSE) down

prod-logs:
	docker compose $(PROD_COMPOSE) logs -f roche-nxt-web

prod-save: build-web
	@mkdir -p deploy/images deploy/package
	@echo "Packaging air-gap deployment bundle..."
	docker save roche_nxt_web:latest | gzip > deploy/images/roche_nxt_web.tar.gz
	docker save roche_nxt_analysis:latest 2>/dev/null | gzip > deploy/images/roche_nxt_analysis.tar.gz 2>/dev/null || \
	    echo "  (analysis image not built — skipping)"
	@cp docker-compose.prod.yml deploy/package/docker-compose.yml
	@cp .env.example deploy/package/.env.example
	@cp LICENSE.md deploy/package/README.md 2>/dev/null || true
	@echo ""
	@echo "Customer bundle ready in deploy/images + deploy/package/"
	@echo "Ship these files along with a customer-specific license.json."
