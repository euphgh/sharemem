VCS ?= vcs
UVM_VERSION ?= uvm-1.2

BUILD_DIR := $(CURDIR)/build
SIMV := $(BUILD_DIR)/simv
TB_SOURCE := $(CURDIR)/tb.sv

.PHONY: all compile run clean

all: run

compile: $(SIMV)

$(SIMV): $(TB_SOURCE)
	mkdir -p $(BUILD_DIR)
	cd $(BUILD_DIR) && \
		$(VCS) -full64 -sverilog -ntb_opts $(UVM_VERSION) \
			-timescale=1ns/1ps \
			$(TB_SOURCE) \
			-o $(SIMV) \
			-l compile.log

run: $(SIMV)
	cd $(BUILD_DIR) && $(SIMV) -l run.log

clean:
	rm -rf $(BUILD_DIR)

