SHELL := /bin/bash

.PHONY: inspect test test-full reconcile degraded clean

inspect:
	./scripts/inspect.sh

test:
	./scripts/run-lab.sh

test-full:
	ALLOW_BREAK_GLASS=1 ALLOW_POD_RESTART=1 ./scripts/run-lab.sh

reconcile:
	ALLOW_POD_RESTART=1 ./scripts/test-reconcile.sh

degraded:
	./scripts/test-degraded.sh

clean:
	./scripts/cleanup.sh
