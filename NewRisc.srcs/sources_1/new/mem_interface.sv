interface MemInterface;
	logic clk;
	logic[31:0] addr;
	logic[31:0] r_data;
	logic[31:0] w_data;
	logic w_enable;
	logic r_enable;
	logic done;
	modport Initiator(
		output clk,
		output addr,
		output w_data,
		output w_enable,
		output r_enable,
		input r_data,
		input done
	);
	modport Target (
		input clk,
		input addr,
		input w_data,
		input w_enable,
		input r_enable,
		output r_data,
		output done
	);
endinterface
