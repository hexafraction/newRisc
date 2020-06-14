`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/14/2020 02:01:31 PM
// Design Name: 
// Module Name: decode_unit_seq_test
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


module decode_unit_seq_test import decoding::*; ();
    
    LongInstructionWord liw;
    
    reg[31:0] pc = 32'h03c00000;
    reg[31:0] ins = 32'h0;
    reg clk = 0;
    PipelineLink dummyPipeline();
    SpeculationControl dummySpeculation();
    MemInterface dummyImem();
    decode_unit dut(.clk(clk), 
        .ins(ins), 
        .pc(pc), 
        .renamed(liw), 
        .to_issue_unit(dummyPipeline.Source), 
        .speculation(dummySpeculation.Watcher),
        .l1i_cache(dummyImem.Initiator)
    );
    
    
    initial begin
        #5 ins = 32'h01404857; // mov 4<-8, 5<-7
        #5 clk = 1;
        
        #5 clk = 0; pc = pc + 4; ins = 32'h01404758; // mov 4<-7, 5<-8
        #5 clk = 1;
        
        #5 clk = 0; pc = pc + 4; ins = 32'h01401425; // mov 1<-4, 2<-5
        #5 clk = 1;
        
        #5 clk = 0; pc = pc + 4; ins = 32'h0140bccb; // mov 11<-12, 12<-11
        #5 clk = 1;
        #5 clk = 0; pc = pc + 4; ins = 32'h0140bccb; // mov 11<-12, 12<-11
        #5 clk = 1;
        #5 clk = 0; pc = pc + 4; ins = 32'h0140bccb; // mov 11<-12, 12<-11
        #5 clk = 1;
        #5 clk = 0; pc = pc + 4; ins = 32'h0140bccb; // mov 11<-12, 12<-11
        #5 clk = 1;
        
        
        #5 clk = 0; pc = pc + 4; ins = 32'h0100ff00; // mov 15<-15
        #5 clk = 1;
        #5 clk = 0; pc = pc + 4; ins = 32'h0100ff00; // mov 15<-15
        #5 clk = 1;
        #5 clk = 0; pc = pc + 4; ins = 32'h0100ff00; // mov 15<-15
        #5 clk = 1;
        #5 clk = 0; pc = pc + 4; ins = 32'h0100ff00; // mov 15<-15
        #5 clk = 1;
        
    end
    
endmodule
