.PHONY: install monitor api frontend bootstrap

ENV_FILE := $(CURDIR)/.env

# Load .env, stripping SCAN_CRON (shell glob expansion breaks xargs)
define load_env
	$(shell grep -v '^\#' $(ENV_FILE) | grep -v 'SCAN_CRON' | sed 's/^/export /' | tr '\n' ';')
endef

install:
	cd api && pnpm install
	cd frontend && pnpm install

bootstrap: install
	cd api && \
		export $$(grep -v '^\#' $(ENV_FILE) | grep -v 'SCAN_CRON' | xargs) && \
		SCAN_CRON='0 */2 * * *' pnpm run bootstrap

monitor:
	@echo "Starting monitoring API on :3001 and dashboard on :5173"
	@trap 'kill 0' INT; \
		( cd api && \
			export $$(grep -v '^\#' $(ENV_FILE) | grep -v 'SCAN_CRON' | xargs) && \
			SCAN_CRON='0 */2 * * *' pnpm dev ) & \
		( cd frontend && pnpm dev ) & \
		wait

api:
	cd api && \
		export $$(grep -v '^\#' $(ENV_FILE) | grep -v 'SCAN_CRON' | xargs) && \
		SCAN_CRON='0 */2 * * *' pnpm dev

frontend:
	cd frontend && pnpm dev
