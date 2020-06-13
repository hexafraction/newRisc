`timescale 1ns / 1ps
// In-order, pipelined
// Pipeline as follows:
// RD: The register file is read if any input datapaths reference a register. This stage may stall (refuse to issue an instruction) due to hazards.
// EX: The instruction is issued to a functional unit, or directly to retirement (FU_NONE). 
//      FU_ALU: A single cycle is taken to compute the ALU output, yielding one result value.
//      FU_WIDEFN: A single cycle is taken to compute the wide function, yielding two result values.
//      FU_SHIFT: A bunch of cycles are taken to perform a shift (for pedagogical/debugging reasons). I know a barrel shifter would be faster
//      FU_MEM: An indeterminate number of cycles is taken to perform a memory operation. This may or may not allow multiple memory ops to be in flight (pipelined)
//      FU_SFR: An inteterminate number of cycles is taken to read or write an SFR (lhs is SFR ID, rhs is value when writing)
//      FU_NONE: L and R are directly sent to the writeback unit as appropriate
// WB: A register value is written back. 
//
// Register file: Two read ports, two write ports (two buffers, one holding odds, one holding evens, each duplicated)
//     On each cycle, the register file can retire up to two register writes (either two functional units returning results, or the wide-function unit).
//         Caveat: The memory is banked, so two writes can be retired only if one is even and one is odd
//     On each cycle, the register file can satisfy up to two reads (from any address, regardless of odd/even)
//
//
// HAZARD VECTOR: 16-bit vector, with a bit set iff any functional unit has a pending write to the corresponding register.
// Analysis of hazards:
// RAW: Possible. Each FU yields a vector of hazard registers based on the in-flight instruction (these get OR'd together and reported to the RD stage),
//      and the RD stage will refuse to read and issue a conflicting register load
// Forwarding is handled in the register file unit (optionally), which handles both RD and WB stages
// WAW and WAR: Probably use the hazard vector as in the RAW case. We don't issue if there's a write still in the pipeline, but that's the slowest option. 
// Can always improve later
// 
// AXI-lite: https://www.realdigital.org/doc/a9fee931f7a172423e1ba73f66ca4081

interface PipelineLink;
	// high when the sink is able to accept an instruction.
	logic readyToAccept;
	// high when the source asserts a valid instruction and wants the sink to accept it.
	logic instructionValid;
	// The instruction itself
	decoding::LongInstructionWord instruction;
	// The data itself (operands before execute stage, outputs after execute stage)
	logic[31:0] lhsData;
	logic[31:0] rhsData;
	// A tag used to identify the instruction.
	logic[3:0] tag;
	// Set if the instruction is speculative and should be held pending branch confirmation
	logic isSpeculative;
	
	modport Source (
			input readyToAccept,
			output instructionValid,
			output instruction, 
			output lhsData,
			output rhsData,
			output tag,
			output isSpeculative);
	modport Sink (
			output readyToAccept,
			input instructionValid,
			input instruction,
			input lhsData,
			input rhsData,
			input tag);
	
endinterface

interface WritebackLink;
	// high when the sink is able to accept a writeback.
	logic readyToAccept;
	// high when the source.asserts a valid writeback and wants the sink to accept it.
	logic writebackValid;
	// This is a physical register number (not an architectural register number)
	logic[4:0] reg_id;
	logic[31:0] reg_data;
	// A tag used to identify the instruction.
	logic[3:0] tag;
	modport Source (
			input readyToAccept,
			output writebackValid,
			output reg_id,
			output reg_data,
			output tag);
	modport Sink (
			output readyToAccept,
			input writebackValid,
			input reg_id,
			input reg_data,
			input tag);
			
endinterface

interface SpeculativeControl;
	// high when a speculative instruction is somewhere in the pipeline
	logic speculatingInPipeline;
	// high when the speculative branch currently in the pipeline has resolved
	logic speculationResolved;
	// When speculativeResolved is high, this indicates that the speculation was correct(0) or incorrect(1)
	// If this is high, the pipeline is flushed
	logic wasMispredicted;
	// when speculationResolved is high, this gives the next PC to issue from
	logic[31:0] nextPc;
	modport Issuer(
		output speculatingInPipeline,
		input speculationResolved,
		input wasMispredicted,
		input nextPc
	);
	modport Resolver(
		input speculatingInPipeline,
		output speculationResolved,
		output wasMispredicted,
		output nextPc
	);
	modport Watcher(
		input speculatingInPipeline,
		input speculationResolved,
		input wasMispredicted,
		input nextPc
	);
endinterface


interface RegisterForwarding;
	// the register being fetched (set by the fetch unit)
	logic[3:0] reg_id;
	// whether an execution unit has the result (wired-or)
	wor valid;
	// the value of the register (wired-or, driven by the execution unit that has the result)
	wor[31:0] value;
	modport ExecutionUnit(
		input reg_id,
		output valid,
		output value
	);
	modport FetchUnit(
		output reg_id,
		input valid,
		input value
	);
endinterface


// Reads program memory and sends an instruction word to the fetch/issue unit, when it can 
// accept one. This unit assigns physical register IDs 
module decode_unit import decoding::*; (
	input clk,
	// temporary, for testing
	input[31:0] ins,
	input[31:0] pc,
	output LongInstructionWord renamed,
	PipelineLink.Source to_issue_unit,
	
	SpeculativeControl.Watcher speculation
);
LongInstructionWord decoded;

// temporary, for testing
always_comb begin
	renamed = decoded;
	renamed.lRead.phys_register_id = 5'b11111;
end
decoder dec(.ins(ins), .pc(pc), .decoded(decoded));
// TODO
endmodule

// The fetch/issue unit performs a fetch from registers. The register fetch is a single clock
// edge on the block RAM, and occurs on the same edge that the instruction is latched into 
// this unit.
module fetch_issue_unit(
	input clk,
	PipelinkLink.Sink from_decode_unit,
	PipelineLink.Source to_alu,
	PipelineLink.Source to_mem,
	// The writeback queue is a single pipeline stage that either passes directly to writeback,
	//     or holds a writeback op until the writeback unit is ready.
	PipelineLink.Source to_writeback_queue,
	// more functional units when they are implemented
	
	SpeculativeControl.Issuer speculation
);
// TODO
endmodule



module cpu_core(
    input clk
    );
endmodule
