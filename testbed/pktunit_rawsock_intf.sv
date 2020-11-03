`timescale 1 ns / 1 ps

module pktunit_rawsock_intf #(
	parameter DATA_BYTES = 8,
	parameter NUM_SOCK = 3,
	parameter string PORT_NAMES = "eth0 eth1 eth2",
	parameter PORT_PROMISC = 32'b1	// Assume max 32 ports
) (
	input  logic clk,
	input  logic deinit,
	output logic [DATA_BYTES*8-1:0] pu_dutin_data_d [NUM_SOCK-1:0],
	output logic pu_dutin_data_v [NUM_SOCK-1:0],
	input  logic pu_dutin_data_r [NUM_SOCK-1:0],
	output logic [7:0] pu_dutin_flags_d [NUM_SOCK-1:0],
	output logic pu_dutin_flags_v [NUM_SOCK-1:0],
	input  logic pu_dutin_flags_r [NUM_SOCK-1:0],
	output logic [DATA_BYTES-1:0] pu_dutin_eop_d [NUM_SOCK-1:0],
	output logic pu_dutin_eop_v [NUM_SOCK-1:0],
	input  logic pu_dutin_eop_r [NUM_SOCK-1:0],
	input  logic [DATA_BYTES*8-1:0] pu_dutout_data_d [NUM_SOCK-1:0],
	input  logic pu_dutout_data_v [NUM_SOCK-1:0],
	output logic pu_dutout_data_r [NUM_SOCK-1:0],
	input  logic [7:0] pu_dutout_flags_d [NUM_SOCK-1:0],
	input  logic pu_dutout_flags_v [NUM_SOCK-1:0],
	output logic pu_dutout_flags_r [NUM_SOCK-1:0],
	input  logic [DATA_BYTES-1:0] pu_dutout_eop_d [NUM_SOCK-1:0],
	input  logic pu_dutout_eop_v [NUM_SOCK-1:0],
	output logic pu_dutout_eop_r [NUM_SOCK-1:0]
);

import "DPI-C" function bit dpiInitRSContext (input int numSocks);
import "DPI-C" function void dpiDeinitRSContext ();
import "DPI-C" function int dpiInitRawSocket (input string ifname, input bit isProm);
import "DPI-C" function bit dpiDeinitRawSocket (input int rsh);

function void split_name (
    output string inames [$],
    input string space_sep_names
);
    int s;
    space_sep_names = {space_sep_names, " "};
    s = 0;
    foreach (space_sep_names[i]) begin
        if (space_sep_names[i] == " ") begin
            inames.push_back(space_sep_names.substr(s, i - 1));
            s = i + 1;
        end
    end
endfunction

int	rsid[NUM_SOCK];
int i;

initial begin
	string pNames [$];
	if (! dpiInitRSContext(NUM_SOCK)) begin
		$display("Failed to initialise DPI socket context.");
		$finish;
	end
	split_name(pNames, PORT_NAMES);
	for (i = 0; i < NUM_SOCK; i++) begin
		rsid[i] = dpiInitRawSocket(pNames[i], PORT_PROMISC[i]);
		if (rsid[i] < 0) begin
			$display("Failed to initialise socket on %s.", pNames[i]);
			$finish;
		end
	end
end

genvar g;
generate
	for (g = 0; g < NUM_SOCK; g++) begin : gen_pu_intf
		pktunit_axis_feeder #(.DATA_BYTES(DATA_BYTES)) pu_dutin_inst
		(
			.clk(clk), .rsh(rsid[g]),
			.data_d(pu_dutin_data_d[g]),
			.data_v(pu_dutin_data_v[g]),
			.data_r(pu_dutin_data_r[g]),
			.flags_d(pu_dutin_flags_d[g]),
			.flags_v(pu_dutin_flags_v[g]),
			.flags_r(pu_dutin_flags_r[g]),
			.eop_d(pu_dutin_eop_d[g]),
			.eop_v(pu_dutin_eop_v[g]),
			.eop_r(pu_dutin_eop_r[g])
		);
		pktunit_axis_poller #(.DATA_BYTES(DATA_BYTES)) pu_dutout_inst
		(
			.clk(clk), .rsh(rsid[g]),
			.data_d(pu_dutout_data_d[g]),
			.data_v(pu_dutout_data_v[g]),
			.data_r(pu_dutout_data_r[g]),
			.flags_d(pu_dutout_flags_d[g]),
			.flags_v(pu_dutout_flags_v[g]),
			.flags_r(pu_dutout_flags_r[g]),
			.eop_d(pu_dutout_eop_d[g]),
			.eop_v(pu_dutout_eop_v[g]),
			.eop_r(pu_dutout_eop_r[g])
		);
	end
endgenerate

always @ (posedge clk) begin
	for (i = 0; i < NUM_SOCK; i++) begin
		if (pu_dutin_data_v[i] & pu_dutin_data_r[i])
			$display("[%d] Data: %x, EOP: %b", i, pu_dutin_data_v[i], pu_dutin_eop_d[i]);
	end
	if (deinit) $finish;
end

endmodule
