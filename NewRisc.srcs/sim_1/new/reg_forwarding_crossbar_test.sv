`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/28/2020 03:56:58 PM
// Design Name: 
// Module Name: reg_forwarding_crossbar_test
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


module reg_forwarding_crossbar_test(

    );
    
    RegisterForwarding prov0();
    RegisterForwarding prov1();
    RegisterForwarding prov2();
    
    RegisterForwarding requester();
    
    reg_forwarding_crossbar_slice #(.NUM_PROVIDERS(3)) dut (
    .providers({prov0.ProviderXbar, prov1.ProviderXbar, prov2.ProviderXbar}),
    .requester(requester.RequesterXbar)
    );
    
    initial begin
        #1 prov0.valid = 0;
        #1 prov0.value = 32'bx;
        #1 prov0.reg_id = 5'bx;
        #1 prov1.valid = 0;
        #1 prov1.value = 32'bx;
        #1 prov1.reg_id = 5'bx;
        #1 prov2.valid = 0;
        #1 prov2.value = 32'bx;
        #1 prov2.reg_id = 5'bx;
        
        #1 requester.reg_id = 5'h14;
        assert(~requester.valid)
            else $error("#ASSERT# requester shouldn't receive valid signal here, since no providers are valid");
        #10 prov1.reg_id = 5'h14;
        assert(~requester.valid)
            else $error("#ASSERT# requester shouldn't receive valid signal here, since no providers are valid");
        #10 prov0.reg_id = 5'h04; prov0.valid = 1;
        assert(~requester.valid)
            else $error("#ASSERT# requester shouldn't receive valid signal here, since the valid provider has the wrong reg id");
        #10 prov1.value = 32'hdeadbeef; prov1.valid = 1;
        assert(~requester.valid)
            else $error("#ASSERT# requester should receive valid signal here, since there's a valid provider with the right reg id");
            
        assert(requester.value == 32'hdeadbeef)
            else $error("#ASSERT# requester got %h, expecting 32'hdeadbeef", requester.value);
        
        #10 prov1.reg_id = 5'h18;
        assert(~requester.valid)
            else $error("#ASSERT# requester shouldn't receive valid signal here, since the provider changed to a different register");
            
            
        #10 requester.reg_id = 5'h00;
        assert(~requester.valid)
            else $error("#ASSERT# requester shouldn't receive valid signal here, since the provider changed to a different register");
        #10 prov2.value = 32'h8BADF00D; prov2.reg_id = 5'h00; prov2.valid = 1; 
        assert(~requester.valid)
            else $error("#ASSERT# requester should receive valid signal here, since there's a valid provider with the right reg id");
            
        assert(requester.value == 32'h8BADF00D)
            else $error("#ASSERT# requester got %h, expecting 32'h8badf00d", requester.value);
            
        #10 prov2.value = 32'h600df00d; 
        assert(~requester.valid)
            else $error("#ASSERT# requester should receive valid signal here, since there's a valid provider with the right reg id");
            
        assert(requester.value == 32'h600df00d)
            else $error("#ASSERT# requester got %h, expecting 32'h600df00d", requester.value);
    end
    
    
endmodule
