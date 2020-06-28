`include "utils.sv"

typedef struct packed {
	reg carry;
	reg parity;
	reg zero;
	reg sign;
} AluFlags;

module alu_pipe import decoding::*;(
	input clk, 
	PipelineLink.Sink from_issue_unit,
	PipelineLink.Source to_wbq,
	RegisterForwarding.Requester alu_oper_in_l,
	RegisterForwarding.Requester alu_oper_in_r,
	RegisterForwarding.Provider alu_rslt_out,
	output reg[31:0] in_flight_writes_out,
	SpeculationControl.Watcher speculation
);


reg occupied;
AluFlags currentFlags;

LongInstructionWord bufferedInstruction;
reg[3:0] bufferedTag;
reg[31:0] lOperand;
reg[31:0] rOperand;
reg lReady;
reg rReady;


logic operandsReady;
assign operandsReady = lReady && rReady;
logic pipeIsAdvancing;
assign from_issue_unit.readyToAccept = pipeIsAdvancing;

AluFunction aluFunction;
AluSignExtension aluSignExt;
logic invert;
logic carryIn;
logic updateFlags;
logic[31:0] result;
AluFlags newFlags;

logic[4:0] outputRegId;
logic enableOutputReg;

alu_core alu_core_inst(
	.lOperand(lOperand),
	.rOperand(rOperand),
	.currentFlags(currentFlags),
	.func(currentFunction),
	.signExt(aluSignExt),
	.invert(invert),
	.carryIn(carryIn),
	.newFlags(newFlags),
	.result(result)
);
	
// pipeline control
always_comb begin
	pipeIsAdvancing = 1'b0;
	if(!occupied) begin
		`ifdef PIPE_DETAILED_DEBUG
			$display("[PIPE  ] ALU accepting; reason: not occupied");
		`endif
		pipeIsAdvancing = 1;
	end
	else if(to_wbq.readyToAccept && operandsReady) begin
		`ifdef PIPE_DETAILED_DEBUG
			$display("[PIPE  ] ALU accepting; reason: writeback ready");
		`endif
		pipeIsAdvancing = 1;
	end
end

always_comb begin
	in_flight_writes_out = 32'b0;
	if(enableOutputReg) begin
		in_flight_writes_out[outputRegId] = 1;
	end
end

// current function and signext calculation
always_comb begin
	/*if(pipeIsAdvancing) begin
		alu_oper_in_l.reg_id = from_issue_unit.instruction.lRead.phys_register_id;
		alu_oper_in_r.reg_id = from_issue_unit.instruction.rRead.phys_register_id;
		enableOutputReg = from_issue_unit.instruction.lWrite.path == DP_REGISTER;
		outputRegId = from_issue_unit.instruction.lWrite.phys_register_id;
		aluFunction = from_issue_unit.instruction.aluFunc;
		aluSignExt = from_issue_unit.instruction.aluSext;
		invert = from_issue_unit.instruction.aluInvertOutput;
		carryIn = from_issue_unit.instruction.aluCarryIn;
		updateFlags = from_issue_unit.instruction.aluUpdateFlags;
	end else begin*/
		// we're probably stalled for some reason
		alu_oper_in_l.reg_id = bufferedInstruction.lRead.phys_register_id;
		alu_oper_in_r.reg_id = bufferedInstruction.rRead.phys_register_id;
		enableOutputReg = bufferedInstruction.lWrite.path == DP_REGISTER;
		outputRegId = bufferedInstruction.lWrite.phys_register_id;
		aluFunction = bufferedInstruction.aluFunc;
		aluSignExt = bufferedInstruction.aluSext;
		invert = bufferedInstruction.aluInvertOutput;
		carryIn = bufferedInstruction.aluCarryIn;
		updateFlags = bufferedInstruction.aluUpdateFlags;
	//end
end

always_comb begin
	to_wbq.instruction = bufferedInstruction;
	to_wbq.lhsData = result;
	to_wbq.lPending = 0;
	to_wbq.tag = bufferedTag;
    to_wbq.instructionValid = (occupied && operandsReady && ~speculation.wasMispredicted);
end


always_ff @ (posedge clk) begin
	if(pipeIsAdvancing) begin
		currentFlags <= newFlags;
	
		bufferedInstruction <= from_issue_unit.instruction;
		bufferedTag <= from_issue_unit.tag;
		// if the issue unit doesn't have an instruction for us, then we have a bubble
		occupied <= from_issue_unit.instructionValid;
		
		// for simulation, pre-set operands to X (synthesis optimizes this properly)
		lOperand <= 32'bx;
		rOperand <= 32'bx;
		 
		
		lReady <= ~from_issue_unit.lPending;
		if(~from_issue_unit.lPending) begin
			lOperand <= from_issue_unit.lhsData;
		end 
		rReady <= ~from_issue_unit.rPending;
		if(~from_issue_unit.rPending) begin
			rOperand <= from_issue_unit.rhsData;
		end
		
		if(from_issue_unit.lPending && alu_oper_in_l.valid) begin
			lOperand <= alu_oper_in_l.value;
			lReady <= 1;
		end	
		if(from_issue_unit.rPending && alu_oper_in_r.valid) begin
			rOperand <= alu_oper_in_r.value;
			rReady <= 1;
		end
	
		
	end else if (occupied) begin
		if(~lReady && alu_oper_in_l.valid) begin
			lOperand <= alu_oper_in_l.value;
			lReady <= 1;
		end	
		if(~rReady && alu_oper_in_r.valid) begin
			rOperand <= alu_oper_in_r.value;
			rReady <= 1;
		end
	end

	
end

always_comb begin
	alu_rslt_out.value = result;
	alu_rslt_out.valid = operandsReady && occupied && enableOutputReg;
	alu_rslt_out.reg_id = outputRegId;
end

endmodule


module alu_core import decoding::*;(
	input[31:0] lOperand,
	input[31:0] rOperand,
	input AluFlags currentFlags,
	input AluFunction func,
	input AluSignExtension signExt,
	input invert,
	input carryIn,
	output AluFlags newFlags,
	output reg[31:0] result
);


logic[31:0] preResult;

always_comb begin
	preResult = 32'bx;
	newFlags.carry = currentFlags.carry;
	case(func) 
		ALU_L:
			preResult = lOperand;
		ALU_R:
			preResult = rOperand;
		ALU_L_PLUS_R:
			{newFlags.carry, preResult} = carryIn ? (lOperand + rOperand) : (lOperand + rOperand + currentFlags.carry);
		ALU_L_MINUS_R:
			{newFlags.carry, preResult} = carryIn ? (lOperand - rOperand) : (lOperand - rOperand - signed'(currentFlags.carry));
		ALU_ZERO:
			preResult = 0;
		ALU_L_AND_R:
			preResult = lOperand & rOperand;
		ALU_L_OR_R:
			preResult = lOperand | rOperand;
		ALU_L_XOR_R:
			preResult = lOperand ^ rOperand;
		default:
			$display("#ALU#### invalid function %s", `STR(currentFunction.name()));
	endcase
	
	result = 32'bx;
	case (signExt) 
		SEXT_NONE: 
			result = preResult ^ {32{invert}};
		SEXT_8_32:
			result = {{24{preResult[7]}}, preResult[7:0]} ^ {32{invert}};
		SEXT_16_32:
			result = {{16{preResult[15]}}, preResult[15:0]} ^ {32{invert}};
		SEXT_24_32:
			result = {{8{preResult[23]}}, preResult[23:0]} ^ {32{invert}};
		default:
			$display("#ALU#### invalid sign extension %s", `STR(currentSignExt.name()));
	endcase
	newFlags.parity = ~result[0];
	newFlags.zero = (result == 0);
	newFlags.sign = (result[31]);
end

endmodule