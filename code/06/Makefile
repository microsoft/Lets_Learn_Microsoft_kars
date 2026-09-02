.PHONY: test unit inspect clean

test:
	./scripts/run-lab.sh

unit:
	./scripts/test-unit.sh

inspect:
	./scripts/inspect.sh

clean:
	kubectl --context kind-kars-dev delete -f manifests/byo-agent-exec-ban.yaml --ignore-not-found
	./scripts/cleanup.sh
