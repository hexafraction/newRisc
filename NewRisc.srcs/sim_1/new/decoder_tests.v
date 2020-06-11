`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/10/2020 08:33:52 PM
// Design Name: 
// Module Name: decoder_tests
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


module decoder_tests import common::*; (

    );
    LongInstructionWord liw;
    
    reg [31:0] insn = 0;
    reg [31:0] pc = 31'h01000000;
    decoder_addresser dut(.ins(insn), .pc(pc), .decoded(liw));
    
    initial begin
        #10 insn[15:0] = 16'hfff5;
        #10
        insn[21:20] = 2'b01;
        #10
        insn[21:20] = 2'b10;
        #10
        insn[21:20] = 2'b11;
        #10 insn[15:0] = 16'h7;
        #10
        insn[21:20] = 2'b00;
        #10
        insn[21:20] = 2'b01;
        #10
        insn[21:20] = 2'b10;
        #10
        insn[21:20] = 2'b11;
    end
endmodule
