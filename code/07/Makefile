.PHONY: test setup unit plan render validate deploy clean

test:
	./scripts/run-lab.sh

setup:
	./scripts/setup-python.sh

unit:
	./scripts/test-unit.sh

plan:
	./scripts/plan-aks.sh

render:
	./scripts/render-gitops.sh

validate: setup render
	./scripts/validate-gitops.sh

deploy:
	./scripts/deploy-aks.sh

clean:
	rm -rf rendered
