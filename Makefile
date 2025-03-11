ps:
	docker compose ps
setup:
	$(MAKE) build
	$(MAKE) install
	$(MAKE) up
build:
	docker compose build
install:
	docker compose run --rm jekyll bundle install
run:
	docker compose up --remove-orphans
stop:
	docker compose down --remove-orphans
