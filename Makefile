.PHONY: build build-analysis build-web up down restart logs status clean rebuild help save test

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
