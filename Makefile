# 1BRC Benchmarking Makefile

# Configuration
JAVA = java
JAVAC = javac
TARGET_DIR = target/classes
SRC_DIR = src/main/java/dev/morling/onebrc
PYTHON = python3
NUM_RUNS = 2
RESULTS_FILE = results.md
MEASUREMENTS_FILE = data/measurements.txt
MEASUREMENTS_1M_FILE = data/measurements-1m.txt

# List of implementations to benchmark
# Note: These work with Java 17. Most top performers require Java 21+
IMPLEMENTATIONS = baseline \
                  spullara \
                  hundredwatt \
                  truelive

# DuckDB variants (3 key configurations)
DUCKDB_VARIANTS = duckdb \
                  duckdb_minimal \
                  duckdb_maxperf

# All implementations including DuckDB variants
ALL_IMPLEMENTATIONS = $(IMPLEMENTATIONS) $(DUCKDB_VARIANTS)

# Default target
.PHONY: all
all: setup benchmark

# Setup target directory and dependencies
.PHONY: setup
setup: setup-duckdb setup-zig
	@mkdir -p $(TARGET_DIR)

# Setup DuckDB - download JDBC driver if needed (silent)
.PHONY: setup-duckdb
setup-duckdb:
	@if [ ! -f lib/duckdb.jar ]; then \
		echo "Downloading DuckDB JDBC driver..."; \
		mkdir -p lib; \
		curl -L -o lib/duckdb.jar https://repo1.maven.org/maven2/org/duckdb/duckdb_jdbc/1.1.3/duckdb_jdbc-1.1.3.jar && \
		echo "  ✓ DuckDB JDBC driver downloaded"; \
	fi

# Setup Zig for fast measurement generation (silent)
.PHONY: setup-zig
setup-zig:
	@if ! command -v zig >/dev/null 2>&1 && [ ! -f zig-linux-x86_64-0.13.0/zig ]; then \
		echo "Installing Zig..."; \
		if [ ! -f zig-linux-x86_64-0.13.0.tar.xz ]; then \
			curl -L -o zig-linux-x86_64-0.13.0.tar.xz https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz; \
		fi; \
		tar -xf zig-linux-x86_64-0.13.0.tar.xz; \
		echo "  ✓ Zig installed"; \
	fi

# Clean - remove all generated files except measurement data
.PHONY: clean
clean:
	@rm -rf $(TARGET_DIR)
	@rm -f .bench_results.txt .bench_temp_*.txt
	@rm -f hs_err_pid*.log
	@rm -rf lib/
	@rm -rf zig-linux-x86_64-0.13.0/
	@rm -f zig-linux-x86_64-0.13.0.tar.xz*
	@rm -f results*.md
	@rm -f create_measurements create_measurements.o
	@echo "Cleaned build artifacts and dependencies"

# Check if 1B measurements exist and link to it
.PHONY: check-data
check-data:
	@if [ ! -f $(MEASUREMENTS_FILE) ]; then \
		echo "Error: $(MEASUREMENTS_FILE) not found."; \
		echo "Generate it with: make generate-1b"; \
		exit 1; \
	fi
	@ln -sf $(MEASUREMENTS_FILE) measurements.txt

# Check if 1M measurements exist for quick test
.PHONY: check-data-1m
check-data-1m:
	@if [ ! -f $(MEASUREMENTS_1M_FILE) ]; then \
		echo "Generating 1M row test file for quick test..."; \
		$(MAKE) -s generate-1m; \
	fi
	@ln -sf $(MEASUREMENTS_1M_FILE) measurements.txt

# Compile a specific implementation
.PHONY: compile-%
compile-%: setup
	@# Handle DuckDB variants
	@if echo "$*" | grep -q "^duckdb"; then \
		if [ ! -f $(TARGET_DIR)/dev/morling/onebrc/CalculateAverage_duckdb.class ]; then \
			echo "Compiling CalculateAverage_duckdb..."; \
			$(JAVAC) -cp lib/duckdb.jar:. -d $(TARGET_DIR) $(SRC_DIR)/CalculateAverage_duckdb.java 2>/dev/null && \
			echo "  ✓ Compiled successfully" || \
			echo "  ✗ Compilation failed"; \
		fi; \
	else \
		echo "Compiling CalculateAverage_$*..."; \
		if [ -f $(SRC_DIR)/CalculateAverage_$*.java ]; then \
			$(JAVAC) -d $(TARGET_DIR) $(SRC_DIR)/CalculateAverage_$*.java 2>/dev/null && \
			echo "  ✓ Compiled successfully" || \
			echo "  ✗ Compilation failed (may require Java 21)"; \
		else \
			echo "  ✗ File not found: CalculateAverage_$*.java"; \
		fi; \
	fi

# Compile all implementations
.PHONY: compile-all
compile-all: $(addprefix compile-,$(IMPLEMENTATIONS))

# Run benchmark for a specific implementation
.PHONY: bench-%
bench-%: compile-%
	@echo "Benchmarking $* ($(NUM_RUNS) runs)..."
	@# Determine the actual class name and JVM options
	@if echo "$*" | grep -q "^duckdb"; then \
		CLASS_NAME="dev.morling.onebrc.CalculateAverage_duckdb"; \
		CLASSPATH="lib/duckdb.jar:$(TARGET_DIR)"; \
		if [ "$*" = "duckdb_minimal" ]; then \
			JVM_OPTS="-Dduckdb.threads=1 -Dduckdb.memory_limit=1GB -Dduckdb.parallel_csv=false"; \
		elif [ "$*" = "duckdb_maxperf" ]; then \
			JVM_OPTS="-Dduckdb.threads=16 -Dduckdb.memory_limit=8GB -Dduckdb.parallel_csv=true"; \
		else \
			JVM_OPTS=""; \
		fi; \
		if [ -n "$$JVM_OPTS" ]; then \
			echo "  Config: $$JVM_OPTS"; \
		fi; \
	else \
		CLASS_NAME="dev.morling.onebrc.CalculateAverage_$*"; \
		if [ ! -f $(TARGET_DIR)/dev/morling/onebrc/CalculateAverage_$*.class ]; then \
			echo "  ✗ Class not found (compilation may have failed)"; \
			exit 1; \
		fi; \
		CLASSPATH="$(TARGET_DIR)"; \
		JVM_OPTS=""; \
	fi; \
	echo "$*" > .bench_temp_$*.txt; \
	for i in $$(seq 1 $(NUM_RUNS)); do \
		echo "  Run $$i/$(NUM_RUNS)..."; \
		start=$$(date +%s.%N); \
		$(JAVA) $$JVM_OPTS -cp $$CLASSPATH $$CLASS_NAME > /dev/null 2>&1; \
		end=$$(date +%s.%N); \
		echo "$$end - $$start" | bc >> .bench_temp_$*.txt; \
	done; \
	$(PYTHON) scripts/calculate_stats.py .bench_temp_$*.txt >> .bench_results.txt; \
	rm -f .bench_temp_$*.txt

# Run standard benchmarks on 1B rows
.PHONY: benchmark
benchmark: check-data
	@echo "Starting benchmark suite on 1B rows..."
	@echo "========================="
	@rm -f .bench_results.txt
	@for impl in $(ALL_IMPLEMENTATIONS); do \
		$(MAKE) -s bench-$$impl; \
	done
	@echo "========================="
	@echo "Generating results..."
	@$(PYTHON) scripts/generate_results.py .bench_results.txt $(RESULTS_FILE)
	@rm -f .bench_results.txt
	@echo "Results written to $(RESULTS_FILE)"

# Run benchmarks on 1M rows
.PHONY: benchmark-1m
benchmark-1m: check-data-1m
	@echo "Starting benchmark suite on 1M rows..."
	@echo "========================="
	@rm -f .bench_results.txt
	@for impl in $(ALL_IMPLEMENTATIONS); do \
		$(MAKE) -s bench-$$impl; \
	done
	@echo "========================="
	@echo "Generating results..."
	@$(PYTHON) scripts/generate_results.py .bench_results.txt results-1m.md
	@rm -f .bench_results.txt
	@echo "Results written to results-1m.md"

# Quick test - single run on 1M rows for speed
.PHONY: quick-test
quick-test: check-data-1m
	@echo "Quick test on 1M rows..."
	@$(MAKE) benchmark-1m NUM_RUNS=1

# Get Zig command helper
define get_zig_cmd
	if command -v zig >/dev/null 2>&1; then \
		echo "zig"; \
	elif [ -f zig-linux-x86_64-0.13.0/zig ]; then \
		echo "./zig-linux-x86_64-0.13.0/zig"; \
	else \
		echo "Error: Zig not found. Run 'make setup' first" >&2; \
		exit 1; \
	fi
endef

# Generate 1M row test data using Zig
.PHONY: generate-1m
generate-1m: setup-zig
	@echo "Generating 1 million rows of test data using Zig..."
	@mkdir -p data
	@ZIG_CMD=$$($(get_zig_cmd)); \
	rm -f create_measurements create_measurements.o; \
	$$ZIG_CMD build-exe -O ReleaseFast src/main/zig/create_measurements.zig 2>/dev/null && \
	./create_measurements 1000000 && \
	mv measurements.txt $(MEASUREMENTS_1M_FILE) && \
	rm -f create_measurements create_measurements.o && \
	echo "✓ Generated 1M rows in $(MEASUREMENTS_1M_FILE)"

# Generate 1B row test data using Zig
.PHONY: generate-1b
generate-1b: setup-zig
	@echo "Generating 1 billion rows of test data using Zig..."
	@echo "  This will take several minutes and create a ~15GB file..."
	@mkdir -p data
	@if [ -f $(MEASUREMENTS_FILE) ]; then \
		echo "  File exists: $(MEASUREMENTS_FILE)"; \
		printf "  Overwrite? [y/N] "; \
		read answer; \
		if [ "$$answer" != "y" ] && [ "$$answer" != "Y" ]; then \
			echo "  Cancelled."; \
			exit 1; \
		fi; \
	fi
	@ZIG_CMD=$$($(get_zig_cmd)); \
	rm -f create_measurements create_measurements.o; \
	$$ZIG_CMD build-exe -O ReleaseFast src/main/zig/create_measurements.zig 2>/dev/null && \
	./create_measurements 1000000000 && \
	mv measurements.txt $(MEASUREMENTS_FILE) && \
	rm -f create_measurements create_measurements.o && \
	echo "✓ Generated 1B rows in $(MEASUREMENTS_FILE)"

# Show available implementations
.PHONY: list
list:
	@echo "Available implementations to benchmark:"
	@echo "Standard implementations:"
	@for impl in $(IMPLEMENTATIONS); do echo "  - $$impl"; done
	@echo ""
	@echo "DuckDB variants:"
	@echo "  - duckdb         (default: all cores, 4GB, parallel)"
	@echo "  - duckdb_minimal (1 thread, 1GB, no parallel)"
	@echo "  - duckdb_maxperf (16 threads, 8GB, parallel)"
	@echo ""
	@echo "Available in repository (may need Java 21):"
	@ls $(SRC_DIR)/CalculateAverage_*.java 2>/dev/null | \
		sed 's|.*/CalculateAverage_||' | sed 's|\.java||' | \
		grep -v "^duckdb$$" | head -10 | sed 's/^/  - /'

# Help target
.PHONY: help
help:
	@echo "1BRC Benchmarking Makefile"
	@echo ""
	@echo "Quick Start:"
	@echo "  make setup        - Install dependencies (DuckDB, Zig)"
	@echo "  make generate-1b  - Generate 1B row test file"
	@echo "  make benchmark    - Run benchmarks on all implementations"
	@echo ""
	@echo "Main Commands:"
	@echo "  make benchmark    - Run all benchmarks on 1B rows"
	@echo "  make quick-test   - Quick test on 1M rows (1 run each)"
	@echo "  make bench-NAME   - Benchmark specific implementation"
	@echo ""
	@echo "Data Generation:"
	@echo "  make generate-1m  - Generate 1M rows (for quick tests)"
	@echo "  make generate-1b  - Generate 1B rows (full dataset)"
	@echo ""
	@echo "Utilities:"
	@echo "  make list         - Show available implementations"
	@echo "  make compile-all  - Compile all implementations"
	@echo "  make clean        - Clean all build artifacts and deps"
	@echo ""
	@echo "Implementations:"
	@echo "  - baseline, spullara, hundredwatt, truelive"
	@echo "  - duckdb, duckdb_minimal, duckdb_maxperf"
