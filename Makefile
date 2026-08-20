.PHONY: check test

check:
	./scripts/check.sh

test:
	python3 -m unittest discover -s tests -v
