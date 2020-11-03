# Make settings
SV_SRCS = \
	sim_top.sv
IP_ZIP = xilinx_com_hls_EtherSwitch_Top_1_0.zip
TOP_MOD = sim_top

# Testbed build constants
BUILD_DIR = build
TB_DIR = testbed
C_SRCS = $(TB_DIR)/rawsock.c
HDL_LIBS = \
	-L smartconnect_v1_0 \
	-L axi_protocol_checker_v1_1_12 \
	-L axi_protocol_checker_v1_1_13 \
	-L axis_protocol_checker_v1_1_11 \
	-L axis_protocol_checker_v1_1_12 \
	-L xil_defaultlib \
	-L unisims_ver \
	-L xpm \
	--lib "ieee_proposed=./ieee_proposed"
XSIM_INIT = "/tools/Xilinx/Vivado/2020.1/data/xsim/ip/xsim_ip.ini"
XIL_PATH = /tools/Xilinx/Vivado/2020.1/bin
XSIM_WD = $(BUILD_DIR)/xsim.dir
WORK_LIB = work
XSIM_SNAPSHOT = $(WORK_LIB).$(TOP_MOD)
PARSE_OUT = $(addprefix $(XSIM_WD)/$(WORK_LIB)/, ${SV_SRCS:.sv=.sdb})
DPI_BINARY = $(XSIM_WD)/$(WORK_LIB)/xsc/dpi.so
IP_LIB_OUT = $(XSIM_WD)/xil_defaultlib/xil_defaultlib.rlx
INTF_LIB_OUT = $(XSIM_WD)/$(WORK_LIB)/pktunit_rawsock_intf.sdb
SIM_BINARY = $(XSIM_WD)/$(XSIM_SNAPSHOT)/xsimk
XSIM_WCFG = testbed.wcfg

sim: $(SIM_BINARY)

$(SIM_BINARY): $(IP_LIB_OUT) $(INTF_LIB_OUT) $(PARSE_OUT) $(DPI_BINARY) 
	cd $(BUILD_DIR); \
	$(XIL_PATH)/xelab $(TOP_MOD) -sv_lib dpi --initfile $(XSIM_INIT) $(HDL_LIBS) -debug all

$(DPI_BINARY): $(C_SRCS)
	cd $(BUILD_DIR); \
	$(XIL_PATH)/xsc ../$(C_SRCS)

$(INTF_LIB_OUT): $(wildcard $(TB_DIR)/*.sv) $(TB_DIR)/xvlog-parse-testbed.prj
	cd $(BUILD_DIR); \
	$(XIL_PATH)/xvlog -prj ../$(TB_DIR)/xvlog-parse-testbed.prj

$(IP_LIB_OUT): $(BUILD_DIR)/xvlog-parse-ip.prj
	cd $(BUILD_DIR); \
	$(XIL_PATH)/xvlog -prj xvlog-parse-ip.prj --initfile $(XSIM_INIT) $(HDL_LIBS)

$(XSIM_WD)/$(WORK_LIB)/%.sdb: %.sv
	cd $(BUILD_DIR); \
	$(XIL_PATH)/xvlog -svlog $(addprefix ../, $<)

$(BUILD_DIR)/xvlog-parse-ip.prj: 
	python3 ./$(TB_DIR)/tbgen.py $(IP_ZIP)

run: sim
	cd $(BUILD_DIR); \
	$(XIL_PATH)/xsim $(XSIM_SNAPSHOT) -R

run_gui: sim
	cd $(BUILD_DIR); \
	$(XIL_PATH)/xsim $(XSIM_SNAPSHOT) -g

run_wave: sim
	cd $(BUILD_DIR); \
	$(XIL_PATH)/xsim $(XSIM_SNAPSHOT) -t ../$(TB_DIR)/dump_wave.tcl

view_wave:
	cd $(BUILD_DIR); \
	$(XIL_PATH)/vivado -source ../$(TB_DIR)/view_wave.tcl

clean:
	rm -rf build/ *.log *.jou *.pb

.PHONY: clean run run_gui run_wave view_wave
