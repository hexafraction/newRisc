// when synthesizing, the name() method of enums is unavailable, even in the $display task.
// This allows the $display to complete successfully while printing dummy text to the synthesis log
`ifdef XILINX_SIMULATOR
`define STR(x) x
`else
`define STR(x) "x"
`endif