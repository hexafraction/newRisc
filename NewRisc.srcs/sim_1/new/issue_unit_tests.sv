`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/18/2020 01:50:24 PM
// Design Name: 
// Module Name: issue_unit_tests
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


/*module fetch_issue_unit import decoding::*; (
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
);*/

module fake_reg_file(
	input clk,
	RegFileFetchInterface.RegFile port1,
	RegFileFetchInterface.RegFile port2
);
	always @ (posedge clk) begin
		port1.r_data <= {3'b0, port1.reg_id, 24'h11};
		port2.r_data <= {3'b0, port2.reg_id, 24'hff};
	end
endmodule

module issue_unit_tests import decoding::*;();
PipelineLink fromDecoder();
PipelineLink toAlu();
PipelineLink toMem();
PipelineLink toWbq();
SpeculationControl spec();
RegFileFetchInterface port1();
RegFileFetchInterface port2();


reg clk = 0;
reg[31:0] inFlightWrites = 0;
int testNumber = 0;

fake_reg_file fake_regs(
	.clk(clk),
	.port1(port1.RegFile),
	.port2(port2.RegFile)
);

fetch_issue_unit dut(
	.clk(clk),
	.from_decode_unit(fromDecoder.Sink),
	.to_alu(toAlu.Source),
	.to_mem(toMem.Source),
	.to_wbq(toWbq.Source),
	.speculation(spec.Issuer),
	.in_flight_writes(inFlightWrites),
	.reg_read_port1(port1.FetchUnit),
	.reg_read_port2(port2.FetchUnit)
);


initial begin
	clk = 0;
	testNumber = 0;
	toAlu.readyToAccept = 0;
	toMem.readyToAccept = 0;
	toWbq.readyToAccept = 0;
	fromDecoder.instructionValid = 0;
	spec.wasMispredicted = 0;
	spec.speculationResolved = 0;
	#5 clk = 1; #5 clk = 0;
	assert (fromDecoder.readyToAccept) 
		else $error("#ASSERT# Issue unit should be ready to accept.");
    
    
	testNumber = 1;
    // issuing an ALU instruction with both operands ready, while the ALU isn't ready yet
    fromDecoder.instruction.pc = 4;
    fromDecoder.instruction.valid = 1;
    fromDecoder.instruction.issueUnit = FU_ALU;
    fromDecoder.instruction.serialize = 0;
    
    fromDecoder.instruction.lRead.path = DP_REGISTER;
    fromDecoder.instruction.lRead.phys_register_id = 5'h13;
    
    fromDecoder.instruction.rRead.path = DP_REGISTER;
    fromDecoder.instruction.rRead.phys_register_id = 5'h04;
    fromDecoder.tag = 4'h1;
    fromDecoder.instructionValid = 1;
    
    #5 clk = 1; #5 clk = 0;
    assert (~fromDecoder.readyToAccept)
        else $error("#ASSERT# should not be trying to accept more while stalled.");
    assert (toAlu.instructionValid)
        else $error("#ASSERT# should have issued to ALU here.");
    assert ((~toMem.instructionValid) && (~toWbq.instructionValid))
        else $error("#ASSERT# should not have issued to mem or wbq here."); 
        
    assert(toAlu.lhsData == 32'h13000011)
        else $error("#ASSERT# wrong LHS data");
    assert(toAlu.rhsData == 32'h040000ff)
        else $error("#ASSERT# wrong RHS data");
    assert((~toAlu.lPending) && (~toAlu.rPending))
        else $error("#ASSERT# L and R should not be pending");
    
    fromDecoder.instructionValid = 0;
    #5 clk = 1; #5 clk = 0;
    assert (~fromDecoder.readyToAccept)
        else $error("#ASSERT# should not be trying to accept more while stalled.");
    assert (toAlu.instructionValid)
        else $error("#ASSERT# should still be trying to issue to ALU.");
        
    assert(toAlu.lhsData == 32'h13000011)
        else $error("#ASSERT# wrong LHS data");
    assert(toAlu.rhsData == 32'h040000ff)
        else $error("#ASSERT# wrong RHS data");
    assert((~toAlu.lPending) && (~toAlu.rPending))
        else $error("#ASSERT# L and R should not be pending still");
        
    toAlu.readyToAccept = 1;
    #5 clk = 1; #5 clk = 0;
    toAlu.readyToAccept = 0;
    assert (~toAlu.instructionValid)
        else $error("#ASSERT# should no longer be trying to issue to ALU.");
     
	 
	testNumber = 2;
    // issuing ALU instructions in quick succession, with a single pending operand in the middle
    fromDecoder.instruction.pc = 4;
    fromDecoder.instruction.valid = 1;
    fromDecoder.instruction.issueUnit = FU_ALU;
    fromDecoder.instruction.serialize = 0;
    
    fromDecoder.instruction.lRead.path = DP_REGISTER;
    fromDecoder.instruction.lRead.phys_register_id = 5'h13;
    
    fromDecoder.instruction.rRead.path = DP_REGISTER;
    fromDecoder.instruction.rRead.phys_register_id = 5'h04;
    fromDecoder.tag = 4'h1;
    fromDecoder.instructionValid = 1;
    
    toAlu.readyToAccept = 1;
	inFlightWrites = 0;
	inFlightWrites[7] = 1;
    #5 clk = 1; #5 clk = 0;
    assert (fromDecoder.readyToAccept)
        else $error("#ASSERT# should be trying to accept, since the pipeline is moving.");
    assert (toAlu.instructionValid)
        else $error("#ASSERT# should have issued to ALU here.");
    assert ((~toMem.instructionValid) && (~toWbq.instructionValid))
        else $error("#ASSERT# should not have issued to mem or wbq here."); 
        
    assert(toAlu.lhsData == 32'h13000011)
        else $error("#ASSERT# wrong LHS data");
    assert(toAlu.rhsData == 32'h040000ff)
        else $error("#ASSERT# wrong RHS data");
    assert((~toAlu.lPending) && (~toAlu.rPending))
        else $error("#ASSERT# L and R should not be pending");
    
    fromDecoder.instruction.rRead.phys_register_id = 5'h05;
    #5 clk = 1; #5 clk = 0;
    assert (fromDecoder.readyToAccept)
        else $error("#ASSERT# should be trying to accept, since the pipeline is moving.");
    assert (toAlu.instructionValid)
        else $error("#ASSERT# should still be trying to issue to ALU.");
        
    assert(toAlu.lhsData == 32'h13000011)
        else $error("#ASSERT# wrong LHS data");
    assert(toAlu.rhsData == 32'h050000ff)
        else $error("#ASSERT# wrong RHS data");
    assert((~toAlu.lPending) && (~toAlu.rPending))
        else $error("#ASSERT# L and R should not be pending still");
        
    fromDecoder.instruction.rRead.phys_register_id = 5'h06;
	
	#5 clk = 1; #5 clk = 0;
    assert (fromDecoder.readyToAccept)
        else $error("#ASSERT# should be trying to accept, since the pipeline is moving.");
    assert (toAlu.instructionValid)
        else $error("#ASSERT# should still be trying to issue to ALU.");
        
    assert(toAlu.lhsData == 32'h13000011)
        else $error("#ASSERT# wrong LHS data");
    assert(toAlu.rhsData == 32'h060000ff)
        else $error("#ASSERT# wrong RHS data");
    assert((~toAlu.lPending) && (~toAlu.rPending))
        else $error("#ASSERT# L and R should not be pending still");
        
	fromDecoder.instruction.rRead.phys_register_id = 5'h07;
	
	#5 clk = 1; #5 clk = 0;
    assert (fromDecoder.readyToAccept)
        else $error("#ASSERT# should be trying to accept, since the pipeline is moving.");
    assert (toAlu.instructionValid)
        else $error("#ASSERT# should still be trying to issue to ALU.");
        
    assert(toAlu.lhsData == 32'h13000011)
        else $error("#ASSERT# wrong LHS data");
    assert((~toAlu.lPending) && (toAlu.rPending))
        else $error("#ASSERT# L should not be pending, R should be pending");
        	    
	fromDecoder.instruction.rRead.phys_register_id = 5'h08;
	
	#5 clk = 1; #5 clk = 0;
    assert (fromDecoder.readyToAccept)
        else $error("#ASSERT# should be trying to accept, since the pipeline is moving.");
    assert (toAlu.instructionValid)
        else $error("#ASSERT# should still be trying to issue to ALU.");
        
    assert(toAlu.lhsData == 32'h13000011)
        else $error("#ASSERT# wrong LHS data");
    assert(toAlu.rhsData == 32'h080000ff)
        else $error("#ASSERT# wrong RHS data");
    assert((~toAlu.lPending) && (~toAlu.rPending))
        else $error("#ASSERT# L and R should not be pending");
		
    fromDecoder.instructionValid = 0;
    #5 clk = 1; #5 clk = 0;
    assert (~toAlu.instructionValid)
        else $error("#ASSERT# should no longer be trying to issue to ALU."); 
    
	inFlightWrites = 0;
end

endmodule
