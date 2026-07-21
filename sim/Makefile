# =============================================================================
# QuestaSim Makefile for UART IP Core
# Usage:
#   make                    — compile & run baud_gen testbench (default)
#   make TB=uart_tx_tb      — compile & run TX testbench
#   make TB=uart_rx_tb      — compile & run RX testbench
#   make TB=uart_top_tb     — compile & run top-level testbench
#   make test               — run the complete self-checking test suite
#   make wave TB=<name>     — open waveform viewer
#   make clean              — remove all generated files
# =============================================================================

# QuestaSim tool names
VLIB = vlib
VLOG = vlog
VSIM = vsim

# RTL sources (order matters for dependency resolution)
RTL = ../rtl/uart_baud_gen.v \
      ../rtl/uart_tx.v       \
      ../rtl/uart_rx.v       \
      ../rtl/uart_top.v

# Testbench directory
TB_DIR = ../testbench

# Default testbench — override with: make TB=uart_tx_tb
TB = uart_baud_gen_tb
TBS = uart_baud_gen_tb uart_tx_tb uart_rx_tb uart_top_tb

# =============================================================================
# Targets
# =============================================================================

.PHONY: all compile run test wave clean

all: run

work:
	$(VLIB) work

compile: work
	$(VLOG) +acc $(RTL)
	$(VLOG) +acc $(TB_DIR)/$(TB).v

run: compile
	$(VSIM) -c -voptargs=+acc $(TB) -l $(TB).log -do "run -all; quit -f"
	@grep -Fq "[PASS]" $(TB).log || \
		(echo "[FAIL] $(TB) did not complete successfully"; exit 1)

test:
	@set -e; \
	for tb in $(TBS); do \
		echo "==> Running $$tb"; \
		$(MAKE) --no-print-directory run TB=$$tb; \
	done

wave: compile
	$(VSIM) -gui -voptargs=+acc $(TB) -do "set TOP $(TB); do wave.do"

clean:
	rm -rf work modelsim.ini transcript qwave.db *.out *.vcd *.wlf
