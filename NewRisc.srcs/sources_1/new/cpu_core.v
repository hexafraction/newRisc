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
package common;
    // DP_REGISTER reads/writes a single register given in register_id
    // DP_IMMEDIATE_DISCARD uses the immediate value for reading, and discards writes
    // DP_PC is used for an indirect (computed) jump
    typedef enum reg[1:0] {DP_REGISTER, DP_IMMEDIATE_DISCARD, DP_PC} DataPath; 
    // FU_NONE passes through both operands to the two outputs.
    // FU_ALU reads two 32-bit inputs, and yields a single 32-bit output (via the lWrite datapath) and a new set of flags.
    // FU_WIDE reads two 32-bit inputs, and multiplies them into a 64-bit output (via the lWrite and rWrite datapaths), or shifts lhs by an amount specified in rhs
    // FU_MEMORY performs loads, stores, exchanges. The address is in lhs, store data in rhs, load/xhcg result in output lhs
	// FU_SFR performs SFR input/output.
    // FU_BRANCH_CONTROL is used to execute a branch
    //      Special case: FU_BRANCH_CONTROL can prevent the retire unit from retiring instructions until the branch resolves
    //      It does so with cooperation of the issue unit: when an instruction is executing on the branch control unit, the issue unit flags instructions
    //      as speculative. Speculative instructions do not retire until the branch control unit indicates a correctly taken speculative branch
    //      A second branch will NOT issue while the first branch is still resolving in the branch control unit.
    // FU_LEA computes base/offset/stride addresses by evaluating lhs + (rhs * imm). 
    //      Special case: LEA takes its two datapath inputs and also always reads the immediate from the long function word.
    typedef enum reg[2:0] {FU_NONE = 0, FU_ALU = 1, FU_WIDE = 2, FU_MEMORY = 3, FU_SFR = 4, FU_BRANCH_CONTROL = 5, FU_LEA = 6} FunctionalUnit;
    
    typedef enum reg[2:0] {ALU_ZERO = 0, ALU_L = 1, ALU_R = 2, ALU_L_PLUS_R = 3, ALU_L_MINUS_R = 4, ALU_L_AND_R = 5, ALU_L_OR_R = 6, ALU_L_XOR_R = 7} AluFunction;
    
    typedef enum reg[1:0] {SEXT_NONE = 0, SEXT_8_32 = 1, SEXT_16_32 = 2, SEXT_24_32 = 3} AluSignExtension;
    
    typedef enum reg {WFN_SHIFT = 0, WFN_MULT = 1} WideFunction;
    typedef enum reg[1:0] {MEM_LOAD = 0, MEM_STORE = 1, MEM_XCHG = 2} MemoryFunction;
    typedef enum reg {SFR_READ = 0, SFR_WRITE = 1} SfrFunction;
   
    
    typedef struct packed {
        DataPath path;
        reg [3:0] register_id;
        // 16-bit immediates in the instruction stream are convereted to 32-bit values as follows:
        // For relative memory addressing, the immediate (signed 16-bit integer) is added to $PC
        // For all other operands, the immediate is either zero- or sign-extended depending on the instruction encoding.
        reg [31:0] immediate_value;
    } DataPathControl;
    
    typedef struct packed {
        // Instruction validity
        reg valid;
    
        // Overall pipeline control
        FunctionalUnit issueUnit;
        // Whether the pipeline must drain after this instruction is issued
        reg serialize;
    
        // ALU control
        AluFunction aluFunc;
        AluSignExtension aluSext;
        // Whether the ALU output ought to be inverted
        reg aluInvertOutput;
        
        // Data path control (where to read/write operands, etc)
        DataPathControl lRead;
        DataPathControl rRead;
        DataPathControl lWrite;
        DataPathControl rWrite;
        
        /* Branch control:
        If we are branching in any way, isBranching is true.
        If we can make a branch prediction, we set predictionValid to true and predictTaken to reflect our prediction.
        This is NOT taken for indirected (register-valued) jumps. Those just serialize.
        */
        reg isBranching;
        reg predictionValid;
        reg predictTaken;
        reg [31:0] addressIfTaken;
        reg [31:0] addressIfNotTaken;
        
        // Wide function control
        WideFunction wideFunction;
        // Memory control
        MemoryFunction memFunction;
		// SFR control
		SfrFunction sfrFunction;
    } LongInstructionWord;
    
endpackage

// Generates control signals and read/write addresses for each path
module decoder_addresser import common::*; (
    input clk,
    // The 32-bit instruction word from the instruction stream
    input [31:0] ins,
    // The program counter associated with the current instruction
    input [31:0] pc,
    
    output LongInstructionWord decoded
);
    
    reg [31:0] interpreted_immediate;
    // For instructions acting on an interpreted immediate, the encoding is as follows:
    // [X X X X X X X X][Y Y C C A A A A][B B B B B B B B B B B B B B B B]
    // X is the major opcode
    // Y is the sub opcode
    // A is the register
    // B is the 16-bit immediate value
    // C is the immediate interpretation:
    //      00 for zext
    //      01 for sext
    //      10 for PC-relative
    //      11 for shifted << 16
    //
    // This is limited to instructions that take a single register argument (i.e. load immediate)
    always_comb begin
        case(ins[21:20])
            2'b00:
                interpreted_immediate <= ins[15:0];
            2'b01:
                interpreted_immediate <= signed'(ins[15:0]);
            2'b10:
                interpreted_immediate <= pc + 32'(signed'(ins[15:0]));
            2'b11:
                interpreted_immediate <= {ins[15:0], 16'b0};
        endcase
    end
    
    always_comb begin
        // By default, decode a NOP-like instruction, but with valid flag set to 0
        decoded.valid <= 0;
        decoded.issueUnit <= FU_NONE;
        decoded.serialize <= 0;
        decoded.aluFunc <= ALU_ZERO;
        decoded.aluSext <= SEXT_NONE;
        decoded.aluInvertOutput <= 0;
        
        decoded.lRead.path <= DP_IMMEDIATE_DISCARD;
        decoded.lRead.register_id <= 4'bx;
        decoded.lRead.immediate_value <= 32'bx;
        
        decoded.rRead.path <= DP_IMMEDIATE_DISCARD;
        decoded.rRead.register_id <= 4'bx;
        decoded.rRead.immediate_value <= 32'bx;
        
        decoded.lWrite.path <= DP_IMMEDIATE_DISCARD;
        decoded.lWrite.register_id <= 4'bx;
        decoded.lWrite.immediate_value <= 32'bx;
        
        decoded.rWrite.path <= DP_IMMEDIATE_DISCARD;
        decoded.rWrite.register_id <= 4'bx;
        decoded.rWrite.immediate_value <= 32'bx;
        
        decoded.isBranching <= 0;
        decoded.predictionValid <= 1'bx;
        decoded.predictTaken <= 1'bx;
        
        decoded.addressIfTaken <= 32'bx;
        decoded.addressIfNotTaken <= pc + 4;
        
        decoded.wideFunction = WFN_SHIFT;
        decoded.memFunction = MEM_LOAD;

        case(ins[31:24])
            // 0x00 - NOPs
            8'h00: begin
                // Remaining three bits can contain arbitrary data
                decoded.valid <= 1;
            end
            // 0x02-0x03 - Loads, moves, and stores
            8'h02: begin
                case(ins[23:22])
                2'b00: begin
                    // Load 16-bit immediate (0000 0001 00...)
                    //  31     24        23   20       16 15                            0
                    // [0 0 0 0 0 0 0 1][0 0 C C A A A A][B B B B B B B B B B B B B B B B]
                    // A is the destination register ID
                    // B is the 16-bit immediate value
                    // C is the immediate interpretation:
                    //      00 for zext
                    //      01 for sext
                    //      10 for PC-relative
					//      11 for shifted << 16
                    decoded.issueUnit <= FU_NONE;
                    decoded.lRead.path <= DP_IMMEDIATE_DISCARD;
                    decoded.lRead.immediate_value <= interpreted_immediate;
                    decoded.lWrite.path <= DP_REGISTER;
                    decoded.lWrite.register_id <= ins[19:16];
					decoded.valid <= 1;
                    end
                2'b01: begin
                    // Load 32-bit memory, immediate address (0000 0001 01...)
                    //  31     24        23   20       16 15                            0
                    // [0 0 0 0 0 0 0 1][0 1 C C A A A A][B B B B B B B B B B B B B B B B]
                    // A is the destination register ID
                    // B is the 16-bit immediate value
                    // C is the immediate interpretation:
                    //      00 for zext (i.e. lowest 64kiB of memory)
                    //      01 for sext (i.e. lowest 32kiB and highest 32 kiB)					
                    //      10 for PC-relative (i.e. +/- 32 kiB around instruction pointer)
                    //      11 for shifted << 16 (i.e. addresses 0, 64kiB, 128 kiB, ...)
                    decoded.issueUnit <= FU_MEMORY;
					decoded.memFunction <= MEM_LOAD;
                    decoded.lRead.path <= DP_IMMEDIATE_DISCARD;
                    decoded.lRead.immediate_value <= interpreted_immediate;
                    decoded.lWrite.path <= DP_REGISTER;
                    decoded.lWrite.register_id <= ins[19:16];
					decoded.valid <= 1;
				end
				2'b01: begin
                    // Store 32-bit memory, immediate address (0000 0001 01...)
                    //  31     24        23   20       16 15                            0
                    // [0 0 0 0 0 0 0 1][0 1 C C A A A A][B B B B B B B B B B B B B B B B]
                    // A is the destination register ID
                    // B is the 16-bit immediate value
                    // C is the immediate interpretation:
                    //      00 for zext (i.e. lowest 64kiB of memory)
                    //      01 for sext (i.e. lowest 32kiB and highest 32 kiB)					
                    //      10 for PC-relative (i.e. +/- 32 kiB around instruction pointer)
                    //      11 for shifted << 16 (i.e. addresses 0, 64kiB, 128 kiB, ...)
                    decoded.issueUnit <= FU_MEMORY;
					decoded.memFunction <= MEM_STORE;
                    decoded.lRead.path <= DP_IMMEDIATE_DISCARD;
                    decoded.lRead.immediate_value <= interpreted_immediate;
                    decoded.rRead.path <= DP_REGISTER;
                    decoded.rRead.register_id <= ins[19:16];
					decoded.valid <= 1;
				end
				2'b11: begin
					// 32-bit indirect memory operation. 
                    //  31     24       23    20       16 15                            0
                    // [0 0 0 0 0 0 0 1][0 1 C C L x x x][A A A A B B B B x x x x x x x x]
                    // A is the data register
                    // B is the address register
                    // C is 00 for load, 01 for store, 10 for exchange, 11 reserved for future expansion
					// L: reserved for later use (lock)
					decoded.issueUnit <= FU_MEMORY;
					// The address input of the memory unit is AAAA
					decoded.lRead.path = DP_REGISTER;
					decoded.lRead.register_id = ins[11:0];
					// When we're storing or exchanging, the data input is BBBB.
					// When we're loading, this is ignored.
					decoded.rRead.path = DP_REGISTER;
					decoded.rRead.register_id = ins[15:12];
					case(ins[21:20])
					2'b00: begin
						// Load value in memory address [AAAA] to register BBBB
						decoded.memFunction = MEM_LOAD;
						decoded.lWrite.path = DP_REGISTER;
						decoded.lWrite.register_id = ins[15:12];
						decoded.valid <= 1;
					end
					2'b01: begin
						// Store value of register AAAA to address in register BBBB
						decoded.memFunction = MEM_STORE;
						decoded.valid <= 1;
					end
					2'b10: begin
						// Exchange between memory address [AAAA] and register BBBB
						decoded.memFunction = MEM_XCHG;
						decoded.lWrite.path = DP_REGISTER;
						decoded.lWrite.register_id = ins[15:12];
						decoded.valid <= 1;
					end
					endcase // ins[21:20]
				end
                endcase // ins[23:22]
            end
        endcase // ins[31:24]
    end

endmodule



module cpu_core(

    );
endmodule
