VCS ?= vcs
UVM_VERSION ?= uvm-1.2

EXAMPLE_DIR := $(CURDIR)
REPO_ROOT := $(abspath $(EXAMPLE_DIR)/../..)
BUILD_DIR := $(EXAMPLE_DIR)/build
SIMV := $(BUILD_DIR)/simv

SOURCES := \
	$(REPO_ROOT)/ut_shm/env/shm_config_pkg.sv \
	$(REPO_ROOT)/ver_common/clk_if.sv \
	$(REPO_ROOT)/ver_common/vlm_memory_agent/vlm_memory_interface.sv \
	$(REPO_ROOT)/ver_common/vlm_reservation_agent/vlm_reservation_interface.sv \
	$(REPO_ROOT)/ver_common/vlm_reservation_agent/vlm_reservation_pkg.sv \
	$(REPO_ROOT)/design/RpuShmTop.sv \
	$(EXAMPLE_DIR)/tb.sv

AGENT_HEADERS := $(wildcard $(REPO_ROOT)/ver_common/vlm_reservation_agent/*.svh)

.PHONY: all compile clean

all: compile

compile: $(SIMV)

$(SIMV): $(SOURCES) $(AGENT_HEADERS)
	mkdir -p $(BUILD_DIR)
	cd $(BUILD_DIR) && \
		$(VCS) -full64 -sverilog -ntb_opts $(UVM_VERSION) \
			-timescale=1ns/1ps \
			+incdir+$(REPO_ROOT)/ver_common/vlm_reservation_agent \
			$(SOURCES) \
			-top tb \
			-o $(SIMV) \
			-l compile.log

clean:
	rm -rf $(BUILD_DIR)
