.PHONY: test render validate deploy verify suspend resume rollback clean

test:
	./scripts/run-lab.sh

render:
	./scripts/render.sh

validate: render
	./scripts/validate.sh

deploy:
	./scripts/deploy-existing-aks.sh

verify:
	./scripts/verify-azure.sh

suspend:
	./scripts/suspend.sh

resume:
	./scripts/resume.sh

rollback:
	./scripts/rollback.sh

clean:
	rm -rf rendered
