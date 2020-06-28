`timescale 1ns / 1ps

module reg_forwarding_crossbar_slice #(
parameter NUM_PROVIDERS=7
)(
    RegisterForwarding.ProviderXbar providers[NUM_PROVIDERS-1:0],
    RegisterForwarding.RequesterXbar requester
);

logic[NUM_PROVIDERS-1:0] intermediate_valid;
// vivado synthesis is really stupid sometimes and doesn't properly handle array reduction methods
// This is an ugly workaround
logic[NUM_PROVIDERS-1:0] intermediate_values[31:0];

genvar j;
genvar k;
generate
    for(j=0; j < NUM_PROVIDERS; j++) begin
        assign intermediate_valid[j] = (providers[j].valid && (requester.reg_id == providers[j].reg_id));
        for(k=0; k < 32; k++) begin
            assign intermediate_values[k][j] = intermediate_valid[j] ? providers[j].value[k] : 1'b0;
        end
    end
    assign requester.valid = |intermediate_valid;
    
    for(k=0; k < 32; k++) begin
        assign requester.value[k] = |(intermediate_values[k]);
    end
endgenerate

endmodule
