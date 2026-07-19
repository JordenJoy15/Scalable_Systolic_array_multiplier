# cocotb + Icarus Verilog Makefile for the systolic array core
# usage:  make            (runs all tests)
#         make WAVES=1    (also dumps waves.vcd -- add $dumpvars support if needed)

SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# core_wrap.v pulls in everything else via `include`
VERILOG_SOURCES = $(PWD)/core_wrap.v
COMPILE_ARGS += -I$(PWD)

TOPLEVEL = core_wrap
MODULE = test_core_wrap

include $(shell cocotb-config --makefiles)/Makefile.sim
