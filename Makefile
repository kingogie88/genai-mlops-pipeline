.PHONY: setup test lint format clean build run deploy

# Development Setup
setup:
	python -m venv venv
	. venv/bin/activate && pip install -r requirements.txt
	pre-commit install

# Testing
test:
	pytest tests/ --cov=src --cov-report=xml --cov-report=term-missing

# Code Quality
lint:
	flake8 src/ tests/
	mypy src/ tests/
	black --check src/ tests/
	isort --check-only src/ tests/

format:
	black src/ tests/
	isort src/ tests/

# Cleaning
clean:
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	find . -type f -name "*.pyd" -delete
	find . -type f -name ".coverage" -delete
	find . -type f -name "coverage.xml" -delete
	find . -type d -name "*.egg-info" -exec rm -rf {} +
	find . -type d -name "*.egg" -exec rm -rf {} +
	find . -type d -name ".pytest_cache" -exec rm -rf {} +
	find . -type d -name ".mypy_cache" -exec rm -rf {} +
	find . -type d -name ".coverage" -exec rm -rf {} +
	find . -type d -name "htmlcov" -exec rm -rf {} +
	rm -rf build/
	rm -rf dist/
	rm -rf .eggs/

# Docker Operations
build:
	docker-compose build

run:
	docker-compose up

stop:
	docker-compose down

# Model Training
train:
	python src/training/trainer.py --config configs/training.yaml

# Deployment
deploy-dev:
	terraform -chdir=infrastructure/terraform/dev init
	terraform -chdir=infrastructure/terraform/dev apply

deploy-prod:
	terraform -chdir=infrastructure/terraform/prod init
	terraform -chdir=infrastructure/terraform/prod apply

# Documentation
docs-serve:
	mkdocs serve

docs-build:
	mkdocs build

# Data Operations
data-sync:
	dvc pull
	dvc repro

# Security
security-check:
	bandit -r src/
	safety check

# Default
all: setup lint test 