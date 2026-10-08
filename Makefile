.PHONY: benchmark validate test-bench run-bench help

# ClassRoom Engine Master Makefile

benchmark:
	@chmod +x tools/bench/run_all.sh
	@./tools/bench/run_all.sh

validate:
	@python3 tools/bench/validate_dataset.py --dataset-dir data/benchmark

test-bench:
	@python3 tools/bench/tests/test_metrics.py

run-bench:
	@python3 tools/bench/run_experiment.py --experiment all

report:
	@python3 tools/bench/make_report.py
	@python3 tools/bench/check_reproducibility.py

help:
	@echo "ClassRoom Benchmark Commands:"
	@echo "  make benchmark   - Regenerate all dataset, logs, plots, tables, and REPORT.md"
	@echo "  make validate    - Validate dataset schema against data/benchmark"
	@echo "  make test-bench  - Run metric library unit tests"
	@echo "  make run-bench   - Execute all benchmark experiments"
	@echo "  make report      - Generate REPORT.md and check reproducibility"
