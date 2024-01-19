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
up:
	docker compose up --remove-orphans
down:
	docker compose down --remove-orphans
