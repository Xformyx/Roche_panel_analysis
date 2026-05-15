.PHONY: build build-analysis build-web up down restart logs status clean rebuild help save test \
        keygen license prod-up prod-down prod-logs prod-save usb-bundle rna-refs check-js

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
	@echo "make check-js       - Validate JavaScript in index.html (requires node + jinja2)"
	@echo ""
	@echo "---- Licensing ----"
	@echo "make keygen         - Generate new Ed25519 signing keypair (run ONCE)"
	@echo "make license CUSTOMER=Name EXPIRES=YYYY-MM-DD [FEATURES=...]"
	@echo "                    - Issue license (omit FEATURES for baseline-only: no longitudinal/igv/hg19_view)"
	@echo ""
	@echo "---- Production (customer) deployment ----"
	@echo "make prod-up        - Start using docker-compose.prod.yml (license required)"
	@echo "make prod-down      - Stop the production stack"
	@echo "make prod-logs      - Tail logs of the production container"
	@echo "make prod-save      - Package image + prod compose into deploy/ for air-gap delivery"
	@echo "make usb-bundle CUSTOMER=\"Name\" LICENSE=path [DATA=1] [DOCKER_FOR=<list|all> | DEBS=/path/to/debs]"
	@echo "                    - Build USB bundle. DOCKER_FOR auto-downloads Docker pkgs."
	@echo "                      Single, comma-list, or 'all' (ubuntu-22.04|ubuntu-24.04|debian-12|rhel-8|rhel-9)."
	@echo "                      Example: DOCKER_FOR=ubuntu-22.04,ubuntu-24.04,rhel-9"
	@echo "make rna-refs [OUT=path/to/rna_refs.tar.gz] [DATA_DIR=/path/to/roche_data]"
	@echo "                    - Pack RNA Panel reference data into a separate tarball."
	@echo "                      Includes: star_index, ctat_lib, gencode GTF, genes.bed12"
	@echo "                      Default output: deploy/rna_refs.tar.gz"
	@echo "                      Install on target: tar xzf rna_refs.tar.gz -C \$$DATA_HOST_DIR"
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
#   - Omit FEATURES (or FEATURES=) for baseline-only: all add-on flags false.
#   - Set EXPIRES=never (or NO_EXPIRY=1) for a perpetual license.
license:
	@test -n "$(CUSTOMER)"  || (echo "ERROR: CUSTOMER is required";  exit 1)
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

# ---------------------------------------------------------------------------
# USB bundle (turnkey offline installer — Docker .deb/.rpm + images + data + license)
#   make usb-bundle CUSTOMER="ABC Hospital" LICENSE=deploy/licenses/abc_hospital.json DATA=1
#   make usb-bundle CUSTOMER="ABC"          LICENSE=...           DEBS=~/docker-debs/ubuntu-22.04
#   make usb-bundle CUSTOMER="ABC"          LICENSE=...           DOCKER_FOR=ubuntu-22.04
#
# DOCKER_FOR     : auto-download Docker offline packages from the internet.
#                  Single distro, comma-separated list, or "all".
#                  Valid distros: ubuntu-22.04 ubuntu-24.04 debian-12 rhel-8 rhel-9
#                  Examples:
#                    DOCKER_FOR=ubuntu-22.04
#                    DOCKER_FOR=ubuntu-22.04,ubuntu-24.04,rhel-9
#                    DOCKER_FOR=all
# DEBS           : use pre-downloaded Docker .deb/.rpm directory instead.
#                  Mutually exclusive with DOCKER_FOR.
# REFRESH_DATA=1 : force re-pack of data/roche_data.tar.gz (default: skip if cached)
# REFRESH_DOCKER=1: force re-download of Docker packages (default: skip if cached)
# ---------------------------------------------------------------------------
usb-bundle:
	@test -n "$(CUSTOMER)" || (echo "ERROR: CUSTOMER is required"; exit 1)
	@test -n "$(LICENSE)"  || (echo "ERROR: LICENSE=<path to license.json> is required"; exit 1)
	@test -f "$(LICENSE)"  || (echo "ERROR: license file not found: $(LICENSE)"; exit 1)
	@if [ -n "$(DEBS)" ] && [ -n "$(DOCKER_FOR)" ]; then \
	    echo "ERROR: DEBS and DOCKER_FOR are mutually exclusive"; exit 1; \
	fi
	@extra=""; \
	if [ -n "$(DATA)" ];           then extra="$$extra --with-data"; fi; \
	if [ -n "$(DEBS)" ];           then extra="$$extra --docker-debs-dir $(DEBS)"; fi; \
	if [ -n "$(DOCKER_FOR)" ];     then extra="$$extra --fetch-docker $(DOCKER_FOR)"; fi; \
	if [ -n "$(OUT)" ];            then extra="$$extra --out $(OUT)"; fi; \
	if [ -n "$(REFRESH_DATA)" ];   then extra="$$extra --refresh-data"; fi; \
	if [ -n "$(REFRESH_DOCKER)" ]; then extra="$$extra --refresh-docker"; fi; \
	bash deploy/build_usb_bundle.sh \
	    --customer "$(CUSTOMER)" \
	    --license  "$(LICENSE)" \
	    $$extra

# ---------------------------------------------------------------------------
# RNA Panel reference data bundle (separate from the main USB bundle)
#   make rna-refs
#   make rna-refs RNA_REFS_OUT=/media/usb/rna_refs.tar.gz
#   make rna-refs DATA_DIR=/custom/path/to/roche_data
#
# Output tarball structure (extract with: tar xzf rna_refs.tar.gz -C $DATA_HOST_DIR):
#   refs/hg38/star_index/
#   refs/hg38/ctat_lib/
#   refs/hg38/gencode.v44.annotation.gtf
#   refs/hg38/genes.bed12
# ---------------------------------------------------------------------------
RNA_REFS_OUT ?= deploy/rna_refs.tar.gz

# Resolve DATA_DIR: honour explicit override, else follow the data/ symlink
_rna_data_dir := $(if $(DATA_DIR),$(DATA_DIR),$(shell \
    if [ -L "$(CURDIR)/data" ]; then readlink -f "$(CURDIR)/data"; \
    elif [ -d "$(CURDIR)/data" ]; then echo "$(CURDIR)/data"; fi))

rna-refs:
	@if [ -z "$(_rna_data_dir)" ] || [ ! -d "$(_rna_data_dir)" ]; then \
	    echo "ERROR: Reference data directory not found."; \
	    echo "       Set DATA_DIR=/path/to/roche_data or ensure data/ symlink exists."; \
	    exit 1; \
	fi
	@HG38="$(_rna_data_dir)/refs/hg38"; \
	missing=""; \
	[ -d "$$HG38/star_index" ]                 || missing="$$missing\n  - refs/hg38/star_index/"; \
	[ -d "$$HG38/ctat_lib" ]                   || missing="$$missing\n  - refs/hg38/ctat_lib/"; \
	[ -f "$$HG38/gencode.v44.annotation.gtf" ] || missing="$$missing\n  - refs/hg38/gencode.v44.annotation.gtf"; \
	[ -f "$$HG38/genes.bed12" ]                || missing="$$missing\n  - refs/hg38/genes.bed12"; \
	if [ -n "$$missing" ]; then \
	    echo "ERROR: The following RNA reference files are missing from $(_rna_data_dir):"; \
	    printf "$$missing\n"; \
	    exit 1; \
	fi
	@echo "Packing RNA Panel reference data..."
	@echo "  Source : $(_rna_data_dir)/refs/hg38/"
	@echo "  Output : $(RNA_REFS_OUT)"
	@echo ""
	@HG38="$(_rna_data_dir)/refs/hg38"; \
	echo "  Sizes:"; \
	du -sh "$$HG38/star_index" "$$HG38/ctat_lib" "$$HG38/gencode.v44.annotation.gtf" "$$HG38/genes.bed12" \
	    | sed 's/^/    /'; \
	echo ""; \
	mkdir -p "$$(dirname "$(RNA_REFS_OUT)")"; \
	tar czf "$(RNA_REFS_OUT)" \
	    -C "$(_rna_data_dir)" \
	    refs/hg38/star_index \
	    refs/hg38/ctat_lib \
	    refs/hg38/gencode.v44.annotation.gtf \
	    refs/hg38/genes.bed12; \
	echo "Done: $(RNA_REFS_OUT) ($$(du -sh "$(RNA_REFS_OUT)" | cut -f1))"
	@echo ""
	@echo "Install on target server:"
	@echo "  tar xzf $$(basename $(RNA_REFS_OUT)) -C \$$DATA_HOST_DIR"

# ── JS syntax validation ──────────────────────────────────────────────────────
# Extracts all <script> blocks from index.html (Jinja2-rendered), then runs:
#   1) Python checks: mangled statements, missing var declarations
#   2) Node.js --check for full syntax validation
#
# Use before building/deploying to catch JS errors early.
# --watch mode requires inotifywait (apt install inotify-tools)
check-js:
	@bash tools/check_js.sh
