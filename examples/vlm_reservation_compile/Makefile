VCS ?= vcs
UVM_VERSION ?= uvm-1.2

EXAMPLE_DIR := $(CURDIR)
REPO_ROOT := $(abspath $(EXAMPLE_DIR)/../..)
BUILD_DIR := $(EXAMPLE_DIR)/build
SIMV := $(BUILD_DIR)/simv
ALIGNMENT_SIMV := $(BUILD_DIR)/alignment_simv
EXTERNAL_BUSY_SIMV := $(BUILD_DIR)/external_busy_simv

SOURCES := \
	$(REPO_ROOT)/ut_shm/util/shm_util_package.sv \
	$(REPO_ROOT)/ver_common/uvc/clock/clk_if.sv \
	$(REPO_ROOT)/ver_common/uvc/vlm_memory_agent/vlm_memory_interface.sv \
	$(REPO_ROOT)/ver_common/uvc/vlm_reservation_agent/vlm_reservation_interface.sv \
	$(REPO_ROOT)/design/RpuTop/src/RpuShm/RpuShmTop.sv \
	$(EXAMPLE_DIR)/tb.sv

AGENT_HEADERS := $(wildcard $(REPO_ROOT)/ver_common/uvc/vlm_reservation_agent/*.svh)
MEMORY_AGENT_FILES := \
	$(wildcard $(REPO_ROOT)/ver_common/uvc/vlm_memory_agent/*.sv) \
	$(wildcard $(REPO_ROOT)/ver_common/uvc/vlm_memory_agent/*.svh)

ALIGNMENT_SOURCES := \
	$(REPO_ROOT)/ut_shm/util/shm_util_package.sv \
	$(REPO_ROOT)/ver_common/uvc/clock/clk_if.sv \
	$(EXAMPLE_DIR)/alignment_tb.sv

EXTERNAL_BUSY_SOURCES := \
	$(REPO_ROOT)/ut_shm/util/shm_util_package.sv \
	$(REPO_ROOT)/ver_common/uvc/clock/clk_if.sv \
	$(REPO_ROOT)/ver_common/uvc/vlm_memory_agent/vlm_memory_interface.sv \
	$(REPO_ROOT)/ver_common/uvc/vlm_reservation_agent/vlm_reservation_interface.sv \
	$(EXAMPLE_DIR)/external_busy_tb.sv

.PHONY: all compile alignment-compile alignment-test external-busy-compile external-busy-test clean

all: compile

compile: $(SIMV)

$(SIMV): $(SOURCES) $(AGENT_HEADERS) $(MEMORY_AGENT_FILES)
	mkdir -p $(BUILD_DIR)
	cd $(BUILD_DIR) && \
		$(VCS) -full64 -sverilog -ntb_opts $(UVM_VERSION) \
			-timescale=1ns/1ps \
			+incdir+$(REPO_ROOT)/ut_shm/util \
			+incdir+$(REPO_ROOT)/ver_common/uvc/vlm_memory_agent \
			+incdir+$(REPO_ROOT)/ver_common/uvc/vlm_reservation_agent \
			$(SOURCES) \
			-top tb \
			-o $(SIMV) \
			-l compile.log

alignment-compile: $(ALIGNMENT_SIMV)

$(ALIGNMENT_SIMV): $(ALIGNMENT_SOURCES) $(AGENT_HEADERS)
	mkdir -p $(BUILD_DIR)
	cd $(BUILD_DIR) && \
		$(VCS) -full64 -sverilog -ntb_opts $(UVM_VERSION) \
			-timescale=1ns/1ps \
			+incdir+$(REPO_ROOT)/ut_shm/util \
			+incdir+$(REPO_ROOT)/ver_common/uvc/vlm_reservation_agent \
			$(ALIGNMENT_SOURCES) \
			-top alignment_tb \
			-o $(ALIGNMENT_SIMV) \
			-l alignment_compile.log

alignment-test: $(ALIGNMENT_SIMV)
	cd $(BUILD_DIR) && $(ALIGNMENT_SIMV) -l alignment_test.log

external-busy-compile: $(EXTERNAL_BUSY_SIMV)

$(EXTERNAL_BUSY_SIMV): $(EXTERNAL_BUSY_SOURCES) $(AGENT_HEADERS)
	mkdir -p $(BUILD_DIR)
	cd $(BUILD_DIR) && \
		$(VCS) -full64 -sverilog -ntb_opts $(UVM_VERSION) \
			-timescale=1ns/1ps \
			+incdir+$(REPO_ROOT)/ut_shm/util \
			+incdir+$(REPO_ROOT)/ver_common/uvc/vlm_reservation_agent \
			$(EXTERNAL_BUSY_SOURCES) \
			-top external_busy_tb \
			-o $(EXTERNAL_BUSY_SIMV) \
			-l external_busy_compile.log

external-busy-test: $(EXTERNAL_BUSY_SIMV)
	cd $(BUILD_DIR) && $(EXTERNAL_BUSY_SIMV) +EXTERNAL_BUSY_PERCENT=100 -l external_busy_test.log

clean:
	rm -rf $(BUILD_DIR)
