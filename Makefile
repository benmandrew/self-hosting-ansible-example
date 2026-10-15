.PHONY: install-deps bootstrap deploy lint test

install-deps:
	ansible-galaxy collection install -r requirements.yml

bootstrap:
	./scripts/bootstrap.sh

deploy:
	ansible-playbook playbooks/site.yml

lint:
	ansible-lint
	ansible-playbook playbooks/site.yml --syntax-check

test:
	./tests/e2e.sh
