SHELL := /bin/bash

.PHONY: build-kars install test build-image deploy status demo security-demo validate destroy

build-kars:
	./scripts/build-kars-latest.sh

install:
	cd workspace-mcp && npm ci

test:
	cd workspace-mcp && npm test

build-image:
	docker build \
		--build-arg NPM_CONFIG_REGISTRY=https://packagefeedproxy.microsoft.io/npm/ \
		-t forge-workspace-mcp:dev workspace-mcp

deploy:
	./scripts/deploy.sh

status:
	kubectl get karssandbox,inferencepolicy,toolpolicy,mcpserver -n kars-system
	kubectl get pods -n kars-mcp

demo:
	./scripts/demo.sh

security-demo:
	./scripts/security-demo.sh

validate:
	./scripts/validate.sh

destroy:
	./scripts/destroy.sh
