SHELL := /bin/bash
.SHELLFLAGS := -e -o pipefail -c
.ONESHELL:

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

VCS ?= vcs
UVM_VERSION ?= uvm-1.2

BUILD_DIR ?= $(REPO_ROOT)/build/ut_shm
SIMV := $(BUILD_DIR)/simv
COMPILE_LOG := $(BUILD_DIR)/compile.log
SMOKE_LOG := $(BUILD_DIR)/smoke.log

RPU_DIR ?= $(REPO_ROOT)/design
TB_DIR ?= $(REPO_ROOT)/ut_shm
VER_CMN ?= $(REPO_ROOT)/ver_common

ifeq ($(origin SNPS_DC_HOME),undefined)
SNPS_DC_HOME := $(BUILD_DIR)/snps_dc_stub
USING_DW_STUB := 1
else
USING_DW_STUB := 0
endif

RTL_FLST := $(TB_DIR)/filelist/shm_dut.f
TB_FLST := $(TB_DIR)/filelist/shm_environment.f \
            $(TB_DIR)/filelist/shm_tbtop.f
TB_TOP_NAME := shm_tb_top

# Options mirrored from ut_shm/cfg/ut_shm.cfg. The cfg file is documentation
# input for this standalone Makefile and is intentionally not parsed here.
RTL_ANA_OPT := -assert svaext +define+RHC_ASSERT_ON
TB_ANA_OPT := +define+SVT_UVM_TECHNOLOGY +define+SYNOPSYS_SV
TB_ELAB_OPT := -debug_access+all +lint=TFIPC-L \
               -cpp g++ -cc gcc -LDFLAGS -Wl,--no-as-needed \
               +notimingchecks +nospecify
TB_COV_OPT := -cm line+cond+fsm+branch+tgl

ENABLE_COVERAGE ?= 0
VCS_USER_OPTS ?=
SIM_ARGS ?= +UVM_TESTNAME=shm_unit_test +TRANS_NUM=0 +UVM_VERBOSITY=UVM_LOW +UVM_TOPOLOGY
SIM_TIMEOUT_SECONDS ?= 120

ifeq ($(ENABLE_COVERAGE),1)
COVERAGE_OPT := $(TB_COV_OPT)
else
COVERAGE_OPT :=
endif

VCS_COMPILE_OPT := -full64 -sverilog -ntb_opts $(UVM_VERSION) \
                   -timescale=1ns/1ps \
                   $(RTL_ANA_OPT) $(TB_ANA_OPT) $(TB_ELAB_OPT) \
                   $(COVERAGE_OPT) $(VCS_USER_OPTS)

export RPU_DIR TB_DIR VER_CMN AXI_VIP_DIR SNPS_DC_HOME

.PHONY: help print-config prepare-build preflight compile smoke clean

help:
	@printf '%s\n' \
	  'ut_shm Ubuntu VCS build entry (repository design stub)' \
	  '' \
	  'Environment variables:' \
	  '  AXI_VIP_DIR   Synopsys AXI/VIP root (required)' \
	  '  RPU_DIR       design/stub root; defaults to <repo>/design' \
	  '  TB_DIR        ut_shm root; defaults to <repo>/ut_shm' \
	  '  VER_CMN       ver_common root; defaults to <repo>/ver_common' \
	  '  SNPS_DC_HOME  Synopsys DesignWare root; an empty build-local' \
	  '                fallback is used while the DUT has no DW cells' \
	  '' \
	  'Targets:' \
	  '  make preflight     validate tools and primary inputs' \
	  '  make compile       run VCS analysis and elaboration' \
	  '  make smoke         compile, then run a zero-transaction UVM test' \
	  '  make print-config  print the resolved build configuration' \
	  '  make clean         remove the guarded build directory' \
	  '' \
	  'Optional variables:' \
	  '  VCS, UVM_VERSION, BUILD_DIR, ENABLE_COVERAGE, VCS_USER_OPTS,' \
	  '  SIM_ARGS, SIM_TIMEOUT_SECONDS'

print-config:
	@printf '%-22s %s\n' \
	  'REPO_ROOT' '$(REPO_ROOT)' \
	  'RPU_DIR' '$(RPU_DIR)' \
	  'TB_DIR' '$(TB_DIR)' \
	  'VER_CMN' '$(VER_CMN)' \
	  'AXI_VIP_DIR' '$(AXI_VIP_DIR)' \
	  'SNPS_DC_HOME' '$(SNPS_DC_HOME)' \
	  'VCS' '$(VCS)' \
	  'UVM_VERSION' '$(UVM_VERSION)' \
	  'BUILD_DIR' '$(BUILD_DIR)' \
	  'RTL_FLST' '$(RTL_FLST)' \
	  'TB_FLST' '$(TB_FLST)' \
	  'TB_TOP_NAME' '$(TB_TOP_NAME)' \
	  'ENABLE_COVERAGE' '$(ENABLE_COVERAGE)' \
	  'USING_DW_STUB' '$(USING_DW_STUB)'

prepare-build:
	@mkdir -p -- '$(BUILD_DIR)'
	if [[ '$(USING_DW_STUB)' == 1 ]]; then
	  mkdir -p -- '$(SNPS_DC_HOME)/dw/sim_ver'
	  printf 'warning: SNPS_DC_HOME is unset; using empty DesignWare fallback: %s\n' \
	    '$(SNPS_DC_HOME)'
	fi

preflight: prepare-build
	@missing=0
	check_var() {
	  local name="$$1"
	  local value="$$2"
	  if [[ -z "$$value" ]]; then
	    printf 'error: required environment variable %s is empty\n' "$$name" >&2
	    missing=1
	  fi
	}
	check_dir() {
	  local label="$$1"
	  local path="$$2"
	  if [[ -n "$$path" && ! -d "$$path" ]]; then
	    printf 'error: %s directory does not exist: %s\n' "$$label" "$$path" >&2
	    missing=1
	  fi
	}
	check_file() {
	  local label="$$1"
	  local path="$$2"
	  if [[ -n "$$path" && ! -f "$$path" ]]; then
	    printf 'error: %s file does not exist: %s\n' "$$label" "$$path" >&2
	    missing=1
	  fi
	}

	check_var AXI_VIP_DIR '$(AXI_VIP_DIR)'

	check_dir RPU_DIR '$(RPU_DIR)'
	check_dir TB_DIR '$(TB_DIR)'
	check_dir VER_CMN '$(VER_CMN)'
	check_dir AXI_VIP_DIR '$(AXI_VIP_DIR)'
	check_dir SNPS_DC_HOME '$(SNPS_DC_HOME)'

	check_file RTL_FLST '$(RTL_FLST)'
	check_file shm_environment.f '$(TB_DIR)/filelist/shm_environment.f'
	check_file shm_tbtop.f '$(TB_DIR)/filelist/shm_tbtop.f'
	check_file RpuShmTop.sv '$(RPU_DIR)/RpuTop/src/RpuShm/RpuShmTop.sv'
	check_file svt_axi.uvm.pkg '$(AXI_VIP_DIR)/include/sverilog/svt_axi.uvm.pkg'
	check_file svt_mem.uvm.pkg '$(AXI_VIP_DIR)/include/sverilog/svt_mem.uvm.pkg'
	check_dir DesignWare '$(SNPS_DC_HOME)/dw/sim_ver'

	if ! command -v -- '$(VCS)' >/dev/null 2>&1; then
	  printf 'error: VCS command is not executable: %s\n' '$(VCS)' >&2
	  missing=1
	fi

	if ((missing)); then
	  exit 2
	fi
	printf 'preflight passed\n'

compile: preflight
	@printf 'compile directory: %s\n' '$(BUILD_DIR)'
	printf 'compile log: %s\n' '$(COMPILE_LOG)'
	cd -- '$(BUILD_DIR)'
	'$(VCS)' $(VCS_COMPILE_OPT) \
	  -f '$(RTL_FLST)' \
	  $(foreach file,$(TB_FLST),-f '$(file)') \
	  -top '$(TB_TOP_NAME)' \
	  -o '$(SIMV)' \
	  -l '$(COMPILE_LOG)'

smoke: compile
	@if ! command -v timeout >/dev/null 2>&1; then
	  printf 'error: timeout command is required for smoke\n' >&2
	  exit 2
	fi
	printf 'smoke log: %s\n' '$(SMOKE_LOG)'
	cd -- '$(BUILD_DIR)'
	timeout '$(SIM_TIMEOUT_SECONDS)'s '$(SIMV)' $(SIM_ARGS) -l '$(SMOKE_LOG)'

clean:
	@build_dir='$(abspath $(BUILD_DIR))'
	case "$$build_dir" in
	  '$(REPO_ROOT)'/build/*) ;;
	  *)
	    printf 'error: refusing to clean unguarded BUILD_DIR: %s\n' "$$build_dir" >&2
	    exit 2
	    ;;
	esac
	rm -rf -- "$$build_dir"
	printf 'removed build directory: %s\n' "$$build_dir"
