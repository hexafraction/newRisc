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
    // 
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
    typedef enum reg[2:0] {FU_NONE = 0, FU_ALU = 1, FU_WIDE = 2, FU_MEMORY = 3, FU_SFR = 4, FU_BRANCH_CONTROL = 5, FU_LEA = 6, FU_DONTCARE = 3'bxxx} FunctionalUnit;
    
    typedef enum reg[2:0] {ALU_L = 0, ALU_R = 1, ALU_L_PLUS_R = 2, ALU_L_MINUS_R = 3, ALU_ZERO = 4, ALU_L_AND_R = 5, ALU_L_OR_R = 6, ALU_L_XOR_R = 7, ALU_DONTCARE = 3'bxxx} AluFunction;
    
    typedef enum reg[1:0] {SEXT_NONE = 0, SEXT_8_32 = 1, SEXT_16_32 = 2, SEXT_24_32 = 3, SEXT_DONTCARE = 2'bxx} AluSignExtension;
    
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
		reg aluCarryIn;
		reg aluUpdateFlags;
        
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


module cpu_core(

    );
endmodule
