`timescale 1ns / 1ps
`include "utils.sv"
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
	// The data itself (operands before execute stage, outputs after execute stage). No meaning in the link between decode and fetch
	logic[31:0] lhsData;
	logic[31:0] rhsData;
	
	// Whether the functional unit should ignore lhsData and/or rhsData, instead waiting for it to be provided via the register forwarding bus
	logic lPending;
	logic rPending;
	
	// A tag used to identify the instruction. (maybe unused?)
	logic[3:0] tag;
	
	modport Source (
			input readyToAccept,
			output instructionValid,
			output instruction, 
			output lhsData,
			output rhsData,
			output tag,
			output lPending,
			output rPending);
	modport Sink (
			output readyToAccept,
			input instructionValid,
			input instruction,
			input lhsData,
			input rhsData,
			input tag,
			input lPending,
			input rPending);
	
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

interface SpeculationControl;
	// high when a speculative instruction is somewhere in the pipeline
	logic speculatingInPipeline;
	// high when the speculative branch currently in the pipeline has resolved
	logic speculationResolved;
	// When speculativeResolved is high, this indicates that the speculation was correct(0) or incorrect(1)
	// If this is high, the pipeline is flushed
	// Assumption/invariant: ~speculationResolved implies ~wasMispredicted
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

// These must be connected via a crossbar switch!
interface RegisterForwarding;
	// the phyisical register being fetched (set by the fetch unit)
	logic[4:0] reg_id;
	// whether an execution unit has the result (wired-or)
	logic valid;
	// the value of the register (wired-or, driven by the execution unit that has the result)
	logic[31:0] value;
	modport Provider(
		input reg_id,
		output valid,
		output value
	);
	modport Requester(
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
	
	SpeculationControl.Watcher speculation,
	MemInterface.Initiator l1i_cache
);
LongInstructionWord decoded;

// We use a very simple remapping of physical to logical registers
// Each logical register maps to two physical registers (i.e. r4 can map to phys4 and phys20)
// phys_msb_mapping[x] indicates the MSB of the physical register to service reads from rx
// (i.e. x if 0, 16+x if 1)
reg[15:0] phys_msb_mapping = 16'h0;
// stores the mapping just before the speculative instruction in the pipeline
// If speculation is wrong, we restore
reg[15:0] speculative_restore_phys_mapping = 16'hx;

always_comb begin
	renamed = decoded;
	
	renamed.lRead.phys_register_id = 5'bx;
	renamed.rRead.phys_register_id = 5'bx;
	renamed.lWrite.phys_register_id = 5'bx;
	renamed.rWrite.phys_register_id = 5'bx;
	// read from the register given in the mapping
	if(renamed.lRead.path == DP_REGISTER) begin
		renamed.lRead.phys_register_id = {phys_msb_mapping[renamed.lRead.register_id], renamed.lRead.register_id};
	end
	
	if(renamed.rRead.path == DP_REGISTER) begin
		renamed.rRead.phys_register_id = {phys_msb_mapping[renamed.rRead.register_id], renamed.rRead.register_id};
	end
	
	
	// Write to the opposite register of the mapping (updated in the always_ff block below)
	if(renamed.lWrite.path == DP_REGISTER) begin
		renamed.lWrite.phys_register_id = {~phys_msb_mapping[renamed.lWrite.register_id], renamed.lWrite.register_id};
	end
	if(renamed.rWrite.path == DP_REGISTER) begin
		renamed.rWrite.phys_register_id = {~phys_msb_mapping[renamed.rWrite.register_id], renamed.rWrite.register_id};
	end
end

always_ff @ (posedge clk) begin
	
	// sim debugging use only. We do this here, so that we only show the values that would be seen by the fetch/issue unit. 
	if(renamed.lRead.path == DP_REGISTER) begin
		$display("[REGMAP] %h %h RD LHS r%x phys%x", pc, ins, renamed.lRead.register_id, renamed.lRead.phys_register_id);
	end
	
	if(renamed.rRead.path == DP_REGISTER) begin
		$display("[REGMAP] %h %h RD RHS r%x phys%x", pc, ins, renamed.rRead.register_id, renamed.rRead.phys_register_id);
	end
	
	
	// Write to the opposite register of the mapping (displays only for sim/debug)
	if(renamed.lWrite.path == DP_REGISTER) begin
		$display("[REGMAP] %h %h WR LHS r%x phys%x", pc, ins, renamed.lWrite.register_id, renamed.lWrite.phys_register_id);
		phys_msb_mapping[renamed.lWrite.register_id] <= ~phys_msb_mapping[renamed.lWrite.register_id];
		$display("[REGMAP] %h %h NEXTRD r%x phys%x", pc, ins, renamed.lWrite.register_id, renamed.lWrite.phys_register_id);
	end
	if(renamed.rWrite.path == DP_REGISTER) begin
		$display("[REGMAP] %h %h WR RHS r%x phys%x", pc, ins, renamed.rWrite.register_id, renamed.rWrite.phys_register_id);		
		phys_msb_mapping[renamed.rWrite.register_id] <= ~phys_msb_mapping[renamed.rWrite.register_id];
		$display("[REGMAP] %h %h NEXTRD r%x phys%x", pc, ins, renamed.rWrite.register_id, renamed.rWrite.phys_register_id);
	end
end


decoder dec(.ins(ins), .pc(pc), .decoded(decoded));
// TODO
endmodule

// The fetch/issue unit performs a fetch from registers. The register fetch is a single clock
// edge on the block RAM, and occurs on the same edge that the instruction is latched into 
// this unit.
module fetch_issue_unit import decoding::*; (
	input clk,
	PipelineLink.Sink from_decode_unit,
	PipelineLink.Source to_alu,
	PipelineLink.Source to_mem,
	// The writeback queue is a single pipeline stage that either passes directly to writeback,
	//     or holds a writeback op until the writeback unit is ready.
	PipelineLink.Source to_wbq,
	// more functional units when they are implemented
	
	SpeculationControl.Issuer speculation,
	
	// Hazard vector: in_flight_writes[n] is set if and only if there is an instruction writing to physical register n in the pipeline.
	// When the instruction reaches writeback, this is no longer asserted (since forwarding will occur via the register file)
	// If this is asserted, then instructions that WRITE that register must NOT be issued, and instructions that read it must wait for a forwarded result before starting computation.
	input[31:0] in_flight_writes,
	RegFileFetchInterface.FetchUnit reg_read_port1,
	RegFileFetchInterface.FetchUnit reg_read_port2
);

// The instruction that's currently in the stage, waiting to be issued to a functional unit.
LongInstructionWord bufferedInstruction;
reg[3:0] bufferedTag;

// whether an instruction is currently in this stage
reg occupied = 0;

// Whether a speculative instruction has been issued and not yet resolved
reg speculatingInPipeline = 0;


// Combinational signal; high if we'll accept an element on the upcoming clock edge.
logic pipeIsAdvancing;
assign from_decode_unit.readyToAccept = pipeIsAdvancing;
logic canIssueSpeculativeInstructions;
logic hazardClear;

always_comb begin
	canIssueSpeculativeInstructions = ~speculatingInPipeline;
	if(speculation.speculationResolved && ~speculation.wasMispredicted) begin
		canIssueSpeculativeInstructions = 1;
	end
end

always_comb begin
	hazardClear = 1;
	if(bufferedInstruction.lWrite.path == DP_REGISTER && in_flight_writes[bufferedInstruction.lWrite.phys_register_id]) begin
		$display("[PIPE  ] fetch unit cannot issue because register r%x already has a pending write", bufferedInstruction.lWrite.phys_register_id);
		hazardClear = 0;
	end
	if(bufferedInstruction.rWrite.path == DP_REGISTER && in_flight_writes[bufferedInstruction.rWrite.phys_register_id]) begin
		$display("[PIPE  ] fetch unit cannot issue because register r%x already has a pending write", bufferedInstruction.rWrite.phys_register_id);
		hazardClear = 0;
	end
end

// pipeline control
always_comb begin
	pipeIsAdvancing = 1'b0;
	if(speculation.speculationResolved && speculation.wasMispredicted) begin
		// uh oh! We've mispredicted. At this point the decoder is still issuing the old stream
		pipeIsAdvancing = 0;
		$display("[PIPE  ] fetch unit not accepting; reason: mispredicted");
	end
	else if(!occupied) begin
		`ifdef PIPE_DETAILED_DEBUG
			$display("[PIPE  ] fetch unit accepting; reason: not occupied");
		`endif
		pipeIsAdvancing = 1;
	end
	// we can only issue speculative instructions if there isn't one already in the pipe
	else if(hazardClear && (canIssueSpeculativeInstructions || ~bufferedInstruction.speculativeBranch)) begin
		pipeIsAdvancing = 0;
		case(bufferedInstruction.issueUnit)
			FU_ALU: begin
				if(to_alu.readyToAccept && to_alu.instructionValid) begin
				`ifdef PIPE_DETAILED_DEBUG
					$display("[PIPE  ] fetch unit accepting; reason: ALU ready");
				`endif
				pipeIsAdvancing = 1;
				end
			end
			FU_MEMORY: begin
				if(to_mem.readyToAccept && to_mem.instructionValid) begin
				`ifdef PIPE_DETAILED_DEBUG
					$display("[PIPE  ] fetch unit accepting; reason: MEM ready");
				`endif
				pipeIsAdvancing = 1;
				end
			end
			FU_NONE: begin
				if(to_wbq.readyToAccept && to_wbq.instructionValid) begin
				`ifdef PIPE_DETAILED_DEBUG
					$display("[PIPE  ] fetch unit accepting; reason: direct writeback ready");
				`endif
				pipeIsAdvancing = 1;
				end
			end
			default: begin
				$display("#PIPE### fetch unit confused; invalid issue unit: %s", 
					`STR(bufferedInstruction.issueUnit.name()));
				pipeIsAdvancing = 1'bx;
			end
		endcase
	end
end

// Computation of reg read addresses
always_comb begin
	if(pipeIsAdvancing) begin
		reg_read_port1.reg_id = from_decode_unit.instruction.lRead.phys_register_id;
		reg_read_port2.reg_id = from_decode_unit.instruction.rRead.phys_register_id;
	end else begin
		// we're stalled, so we should just re-fetch the operands for the instruction that's rotting away in our buffer
		reg_read_port1.reg_id = bufferedInstruction.lRead.phys_register_id;
		reg_read_port2.reg_id = bufferedInstruction.rRead.phys_register_id;
	end
end

logic[31:0] lhsData;
logic[31:0] rhsData;
logic lPending;
logic rPending;

always_comb begin
	lhsData = 32'bx;
	rhsData = 32'bx;
	lPending = 1'b0;
	rPending = 1'b0;
	case(bufferedInstruction.lRead.path)
		DP_REGISTER: begin
			lhsData = reg_read_port1.r_data;
			lPending = in_flight_writes[bufferedInstruction.lRead.phys_register_id];
		end
		DP_IMMEDIATE_DISCARD: begin
			lhsData = bufferedInstruction.lRead.immediate_value;
		end
		DP_PC: begin
			lhsData = bufferedInstruction.pc;
		end
	endcase
	
	case(bufferedInstruction.rRead.path)
		DP_REGISTER: begin
			rhsData = reg_read_port2.r_data;
			rPending = in_flight_writes[bufferedInstruction.rRead.phys_register_id];
		end
		DP_IMMEDIATE_DISCARD: begin
			rhsData = bufferedInstruction.rRead.immediate_value;
		end
		DP_PC: begin
			rhsData = bufferedInstruction.pc;
		end
	endcase
end

// 6/15/2020 notes: continue here. Need to finish the logic that sets up the outgoing data
always_comb begin
	// assignments to outgoing pipeline links go here
	// lhsData/rhsData come from reg file/immediate/PC depending on the datapath [done]
	// lPending/rPending come from the hazard vector && (path == register) [done]
	// tag passes through [done]
	// instructionValid if we are occupied, AND the instruction is clear to go ahead (i.e. no write conflicts)
	//
	//
	// TODO for later:
	// isSpeculative should be left as X for now, until branching and speculative execution are implemented 
	// 		this unit will need to issue `speculatingInPipeline`, and also handle the resolve signals
	// 		on correct prediction, it should continue issuing
	//		on wrong prediction, it should clear out whatever's inside without issuing it
	//		The decode unit will be responsible for refilling the pipeline
	to_alu.instruction = bufferedInstruction;
	to_mem.instruction = bufferedInstruction;
	to_wbq.instruction = bufferedInstruction;
	to_alu.lhsData = lhsData;
	to_mem.lhsData = lhsData;
	to_wbq.lhsData = lhsData;
	to_alu.rhsData = rhsData;
	to_mem.rhsData = rhsData;
	to_wbq.rhsData = rhsData;
	to_alu.lPending = lPending;
	to_mem.lPending = lPending;
	to_wbq.lPending = lPending;
	to_alu.rPending = rPending;
	to_mem.rPending = rPending;
	to_wbq.rPending = rPending;
	
	to_alu.tag = bufferedTag;
	to_mem.tag = bufferedTag;
	to_wbq.tag = bufferedTag;
	
	to_alu.instructionValid = 0;
	to_mem.instructionValid = 0;
	to_wbq.instructionValid = 0;
	// if we mispredicted, we're not sending this instruction out
	if(occupied && ~speculation.wasMispredicted) begin
		case(bufferedInstruction.issueUnit)
			FU_ALU: begin
				to_alu.instructionValid = 1;
			end
			FU_MEMORY: begin
				to_mem.instructionValid = 1;
			end
			FU_NONE: begin
				to_wbq.instructionValid = 1;
			end
			default: begin
				$display("#ISSUE## issue unit confused; invalid issue unit: %s", 
					`STR(bufferedInstruction.issueUnit.name()));
				pipeIsAdvancing = 1'bx;
			end
		endcase
	end
	
end

always_ff @ (posedge clk) begin
	if(speculation.speculationResolved && speculation.mispredicted) begin
		occupied <= 0;
	end
	else if(pipeIsAdvancing) begin
		bufferedInstruction <= from_decode_unit.instruction;
		bufferedTag <= from_decode_unit.tag;
		// if the decoder doesn't have an instruction for us, then we have a bubble
		occupied <= from_decode_unit.instructionValid;
	end
	
	
end
	
endmodule




module cpu_core(
    input clk
    );
endmodule
