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


	reg aluReadsL;
	reg aluReadsR;

	
    always_comb begin

		
        // By default, decode a NOP-like instruction, but with valid flag set to 0
        decoded.valid = 0;
        decoded.issueUnit = FU_DONTCARE;
        decoded.serialize = 0;
        decoded.aluFunc = ALU_DONTCARE;
        decoded.aluSext = SEXT_DONTCARE;
        decoded.aluInvertOutput = 0;
		decoded.aluCarryIn = 0;
		decoded.aluUpdateFlags = 0;
        
        decoded.lRead.path = DP_IMMEDIATE_DISCARD;
        decoded.lRead.register_id = 4'bx;
        decoded.lRead.immediate_value = 32'bx;
        
        decoded.rRead.path = DP_IMMEDIATE_DISCARD;
        decoded.rRead.register_id = 4'bx;
        decoded.rRead.immediate_value = 32'bx;
        
        decoded.lWrite.path = DP_IMMEDIATE_DISCARD;
        decoded.lWrite.register_id = 4'bx;
        decoded.lWrite.immediate_value = 32'bx;
        
        decoded.rWrite.path = DP_IMMEDIATE_DISCARD;
        decoded.rWrite.register_id = 4'bx;
        decoded.rWrite.immediate_value = 32'bx;
        
        decoded.isBranching = 0;
        decoded.predictionValid = 1'bx;
        decoded.predictTaken = 1'bx;
        
        decoded.addressIfTaken = 32'bx;
        decoded.addressIfNotTaken = pc + 4;
        
        decoded.wideFunction = WFN_SHIFT;
        decoded.memFunction = MEM_LOAD;
        decoded.sfrFunction = SFR_READ;
		
		
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
		case(ins[21:20])
            2'b00:
                interpreted_immediate = ins[15:0];
            2'b01:
                interpreted_immediate = signed'(ins[15:0]);
            2'b10:
                interpreted_immediate = pc + 32'(signed'(ins[15:0]));
            2'b11:
                interpreted_immediate = {ins[15:0], 16'b0};
        endcase
		
		
		// False dependency detection for ALU ops
		aluReadsL = 1;
		aluReadsR = 1;
        case(ins[18:16])			
			3'h0: begin
				aluReadsR = 0;
			end
			3'h1: begin
				aluReadsL = 0;
			end
            3'h4: begin
                aluReadsL = 0;
				aluReadsR = 0;
            end
        endcase
		
		// The actual decoding tree starts here
        case(ins[31:24])
            // 0x00 - NOPs
            8'h00: begin
                // Remaining three bits can contain arbitrary data
                decoded.valid = 1;
				decoded.issueUnit = FU_NONE;
				$display("[DECODE] %h %h NOP", pc, ins);
            end
			
            // 0x01 - Moves, sign-extensions, and reg = reg OP reg ALU operations
            8'h01: begin
				if(ins[23]) begin
					// ALU op: bit 23 set. Supports binary operations, moves, and sign-extending moves, 
					// with the ability to update flags.
					//                     22  20  18  16   14  12  10
					// 31            24  23  21  19  17   15  13  11  9 8  7 6 5 4 3 2 1 0             
					// [0 0 0 0 0 0 0 1][1 x x W I F F F][D D D D L L L L][R R R R C U S S]
					// W = 1: Write result. W = 0: Only update flags if Z set.
					// I = 1: invert result of ALU (before computing flags). 0 = do not invert
					// F: the ALU function (see AluFunction field)
					// D: The destination register
					// L: the LHS register
					// R: the RHS register
					// C = 1: carry/borrow in for add/sub. C = 1: Do not carry/borrow in for add/sub (ignore carry flag)
					// U = 1: update flags. U = 0: do not update flags.
					// S: Sign extension control (00 = none, 01 = 8->32, 10 = 16->32, 11 = 24->32)
					// Note: W = 0, Z = 0 creates an effective no-op.
					decoded.issueUnit = FU_ALU;
					if(ins[20]) begin
						decoded.lWrite.path = DP_REGISTER;
						decoded.lWrite.register_id = ins[15:12];
					end
					decoded.aluInvertOutput = ins[19];
					decoded.aluCarryIn = ins[3];
					decoded.aluUpdateFlags = ins[2];
					case(ins[1:0])
					2'b00:
						decoded.aluSext = SEXT_NONE;
					2'b01:
						decoded.aluSext = SEXT_8_32;
					2'b10:
						decoded.aluSext = SEXT_16_32;
					2'b11:
						decoded.aluSext = SEXT_24_32;
					endcase
					case(ins[18:16])
					3'b000:
						decoded.aluFunc = ALU_L;
					3'b001:
						decoded.aluFunc = ALU_R;
					3'b010:
						decoded.aluFunc = ALU_L_PLUS_R;
					3'b011:
						decoded.aluFunc = ALU_L_MINUS_R;					
					3'b100:
						decoded.aluFunc = ALU_ZERO;
					3'b101:
						decoded.aluFunc = ALU_L_AND_R;
					3'b110:
						decoded.aluFunc = ALU_L_OR_R;
					3'b111:
						decoded.aluFunc = ALU_L_XOR_R;
					endcase
					if(aluReadsL) begin
						decoded.lRead.path = DP_REGISTER;
						decoded.lRead.register_id = ins[11:8];
					end
					if(aluReadsR) begin
						decoded.rRead.path = DP_REGISTER;
						decoded.rRead.register_id = ins[7:4];
					end
					decoded.valid = 1;
					$display("[DECODE] %h %h ALU: r%0d <- %s(%s(r%0d, r%0d))", 
						pc, 
						ins,
						decoded.lWrite.register_id,
						decoded.aluSext.name(),
						decoded.aluFunc.name(),
						decoded.lRead.register_id,
						decoded.lWrite.register_id);
				end else begin
					// MOVs: bit 23 clear. This supports only moves; flags are not updated.
					// 31            24  23            16 15            8  7             0             
					// [0 0 0 0 0 0 0 1][0 B x x x x x x][D D D D L L L L][E E E E R R R R]
					// If B is clear, this is MOV DDDD <- LLLL
					// If B is set, this is a double-pumped MOV: MOV DDDD <- LLLL and MOV EEEE <- RRRR 
					// Double-pumped MOVs allow two moves to occur. Because registers are banked,
					// this will stall if both destination regs are even or both are odd.
					// e.g. mov r4 <- r5, r6 <- r5 is legal but slow
					//      mov r4 <- r5, r7 <- r5 is fast because the two writes are on different banks
					//      mov r4 <- r7, r5 <- r8 is illegal because both writes are to the same reg
					// Efficiency warning: if either move must stall due to a hazard, the whole instruction will stall.
					// e.g. LDM r1, 0x1234
					// 		MOV r4 <- r1, r3 <- r2
					// the move from r2 to r3 will also stall because r1 remains a read-after-write hazard.
					decoded.issueUnit = FU_NONE;
					decoded.lRead.path = DP_REGISTER;
					decoded.lRead.register_id = ins[11:8];
					decoded.lWrite.path = DP_REGISTER;
					decoded.lWrite.register_id = ins[15:12];
					
					decoded.valid = 1;
					$display("[DECODE] %h %h MOV r%0d <- r%0d", 
						pc, 
						ins, 
						decoded.lWrite.register_id, 
						decoded.lRead.register_id);
					if(ins[22]) begin
						decoded.rRead.path = DP_REGISTER;
						decoded.rRead.register_id = ins[3:0];
						decoded.rWrite.path = DP_REGISTER;
						decoded.rWrite.register_id = ins[7:4];
						$display("                           MOV r%0d <- r%0d", 
							decoded.rWrite.register_id, 
							decoded.rRead.register_id);
						if(decoded.lWrite.register_id == decoded.rWrite.register_id) begin
							decoded.valid = 0;
							$display("                           ILLEGAL (double MOV to same register)");
						end
					end
				end
            end
			
            // 0x02 - Loads and stores
            8'h02: begin
                case(ins[23:22])
                2'b00: begin
                    // Load 16-bit immediate
                    //  31     24        23   20       16 15                            0
                    // [0 0 0 0 0 0 1 0][0 0 C C A A A A][B B B B B B B B B B B B B B B B]
                    // A is the destination register ID
                    // B is the 16-bit immediate value
                    // C is the immediate interpretation:
                    //      00 for zext
                    //      01 for sext
                    //      10 for PC-relative
					//      11 for shifted << 16
                    decoded.issueUnit = FU_NONE;
                    decoded.lRead.path = DP_IMMEDIATE_DISCARD;
                    decoded.lRead.immediate_value = interpreted_immediate;
                    decoded.lWrite.path = DP_REGISTER;
                    decoded.lWrite.register_id = ins[19:16];
					decoded.valid = 1;
					$display("[DECODE] %h %h LDI r%0d <- #%h", 
						pc, 
						ins, 
						decoded.lWrite.register_id, 
						decoded.lRead.immediate_value);
				end
                2'b01: begin
                    // Load 32-bit memory, immediate address
                    //  31     24        23   20       16 15                            0
                    // [0 0 0 0 0 0 1 0][0 1 C C A A A A][B B B B B B B B B B B B B B B B]
                    // A is the destination register ID
                    // B is the 16-bit immediate value
                    // C is the immediate interpretation:
                    //      00 for zext (i.e. lowest 64kiB of memory)
                    //      01 for sext (i.e. lowest 32kiB and highest 32 kiB)					
                    //      10 for PC-relative (i.e. +/- 32 kiB around instruction pointer)
                    //      11 for shifted << 16 (i.e. addresses 0, 64kiB, 128 kiB, ...)
                    decoded.issueUnit = FU_MEMORY;
					decoded.memFunction = MEM_LOAD;
                    decoded.lRead.path = DP_IMMEDIATE_DISCARD;
                    decoded.lRead.immediate_value = interpreted_immediate;
                    decoded.lWrite.path = DP_REGISTER;
                    decoded.lWrite.register_id = ins[19:16];
					decoded.valid = 1;
					$display("[DECODE] %h %h LDM r%0d <- [%h]", 
						pc, 
						ins, 
						decoded.lWrite.register_id, 
						decoded.lRead.immediate_value);
				end
				2'b10: begin
                    // Store 32-bit memory, immediate address
                    //  31     24        23   20       16 15                            0
                    // [0 0 0 0 0 0 1 0][1 0 C C A A A A][B B B B B B B B B B B B B B B B]
                    // A is the destination register ID
                    // B is the 16-bit immediate value
                    // C is the immediate interpretation:
                    //      00 for zext (i.e. lowest 64kiB of memory)
                    //      01 for sext (i.e. lowest 32kiB and highest 32 kiB)					
                    //      10 for PC-relative (i.e. +/- 32 kiB around instruction pointer)
                    //      11 for shifted << 16 (i.e. addresses 0, 64kiB, 128 kiB, ...)
                    decoded.issueUnit = FU_MEMORY;
					decoded.memFunction = MEM_STORE;
                    decoded.lRead.path = DP_IMMEDIATE_DISCARD;
                    decoded.lRead.immediate_value = interpreted_immediate;
                    decoded.rRead.path = DP_REGISTER;
                    decoded.rRead.register_id = ins[19:16];
					decoded.valid = 1;
					$display("[DECODE] %h %h STM [%h] <- r%0d", 
						pc, 
						ins, 
						decoded.lRead.immediate_value, 
						decoded.rRead.register_id);
				end
				2'b11: begin
					// 32-bit indirect memory operation. 
                    //  31     24       23    20       16 15                            0
                    // [0 0 0 0 0 0 1 0][1 1 C C L x x x][A A A A B B B B x x x x x x x x]
                    // A is the data register
                    // B is the address register
                    // C is 00 for load, 01 for store, 10 for exchange, 11 reserved for future expansion
					// L: reserved for later use (lock)
					decoded.issueUnit = FU_MEMORY;
					// The address input of the memory unit is AAAA
					decoded.lRead.path = DP_REGISTER;
					decoded.lRead.register_id = ins[15:12];
					// When we're storing or exchanging, the data input is BBBB.
					// When we're loading, this is ignored.
					decoded.rRead.path = DP_REGISTER;
					decoded.rRead.register_id = ins[11:8];
					case(ins[21:20])
					2'b00: begin
						// Load value in memory address [AAAA] to register BBBB
						decoded.memFunction = MEM_LOAD;
						decoded.lWrite.path = DP_REGISTER;
						decoded.lWrite.register_id = ins[11:8];
						decoded.valid = 1;
						$display("[DECODE] %h %h LDMI r%0d <- [r%0d]", 
							pc, 
							ins, 
							decoded.lWrite.register_id, 
							decoded.lRead.register_id);
					end
					2'b01: begin
						// Store value of register BBBB to address in register AAAA
						decoded.memFunction = MEM_STORE;
						decoded.valid = 1;
						$display("[DECODE] %h %h STMI [r%0d] <- r%0d", 
							pc, 
							ins, 
							decoded.lWrite.register_id, 
							decoded.lRead.register_id);
					end
					2'b10: begin
						// Exchange between memory address [AAAA] and register BBBB
						decoded.memFunction = MEM_XCHG;
						decoded.lWrite.path = DP_REGISTER;
						decoded.lWrite.register_id = ins[11:8];
						decoded.valid = 1;
						$display("[DECODE] %h %h XHCG r%0d <-> [r%0d]", 
							pc, 
							ins, 
							decoded.lWrite.register_id, 
							decoded.lRead.register_id);
						$display("          XCHG reads from r%0d", decoded.rRead.register_id);
					end
					endcase // ins[21:20]
				end
                endcase // ins[23:22]
            end
        endcase // ins[31:24]
    end

endmodule
