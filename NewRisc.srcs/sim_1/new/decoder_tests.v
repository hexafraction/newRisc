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


module decoder_tests import decoding::*; (

    );
    LongInstructionWord liw;
    
    reg [31:0] insn = 0;
    reg [31:0] pc = 31'h01000000;
    decoder dut(.ins(insn), .pc(pc), .decoded(liw));
    
    initial begin
        #10 insn = 32'h0;
        #10 insn = 32'h01964574; // r12 <- r5 | r7, update flags, no carry in
        #10 insn = 32'h0193857a; // r12 <- SEXT_16_32(r5 | r7), no update flags, carry in
        #10 insn = 32'h01004800; // r4 <- r8
        #10 insn = 32'h01404857; // r4 <- r8, r5 <- r7
        #10 insn = 32'h01405857; // r4 <- r8, r4 <- r7, ILLEGAL
        #10 insn = 32'h0235feff; // r5 <- #0xfeff0000
        #10 insn = 32'h0215feff; // r5 <- #0xfffffeff
        #10 insn = 32'h0205feff; // r5 <- #0x0000feff
        #10 insn = 32'h0225feff; // r5 <- #0x00fffeff
        #10 insn = 32'h0265feff; // r5 <- [0x00fffeff]
        #10 insn = 32'h02a5feff; // r5 -> [0x00fffeff]
        #10 insn = 32'h02c06700; // r7 <- [r6]
        #10 insn = 32'h02d06700; // [r6] <- r7
        #10 insn = 32'h02e06700; // exch r7, [r6]
        
    end
endmodule
