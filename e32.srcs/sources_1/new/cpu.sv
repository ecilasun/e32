`include "shared.vh"

module cpu
	#(
		parameter RESETVECTOR = 32'h00000000	// Default reset vector, change as required per CPU instance
	)
	(
		input wire cpuclock,
		input wire reset,
		output bit [31:0] busaddress = 32'd0,	// memory or device address
		input wire [31:0] din,					// data read from memory
		output bit [31:0] dout = 32'd0,			// data to write to memory
		output bit busre = 1'b0,				// memory read enable
		output bit [3:0] buswe = 4'h0			// memory write enable (byte mask)
	);

// ------------------------------------------------------------------------------------
// Operation
// ------------------------------------------------------------------------------------

// State:			RESET					RETIRE						FETCH							DECODE							EXEC							WBACK
//
// Work done:		Once at startup			Sets up register			Instruction read delay			Latch instruction and			Sets up LOAD/STORE bus			Calculates write back values
//			 		sets up default			write values and			slot.							strobe decoder.					address, enables read			and sets up bus write enable for
//					machine states.			write enable, sets																			for LOAD and sets next PC.		STORE.
//											up next instruction																			Also latch branch flag.
//											read.
//
// Next state:		RETIRE					FETCH						DECODE							EXEC							WBACK							RETIRE

// ------------------------------------------------------------------------------------
// Internals
// ------------------------------------------------------------------------------------

// Reset vector is in S-RAM
bit [31:0] PC = RESETVECTOR;
bit [31:0] nextPC = 32'd0;
bit [31:0] csrval = 32'd0;
bit [31:0] instruction = {25'd0,`OPCODE_OP_IMM,2'b11}; // NOOP (addi x0,x0,0)
bit decen = 1'b0;
bit aluen = 1'b0;
bit branchr = 1'b0;
bit illegalinstruction = 1'b0;

bit ecall = 1'b0;
bit ebreak = 1'b0;
bit wfi = 1'b0;
bit mret = 1'b0;
bit miena = 1'b0;

wire isrecordingform;
wire [17:0] instrOneHot;
wire selectimmedasrval2;
wire [31:0] immed;
wire [4:0] csrindex;
wire [4:0] rs1, rs2, rs3, rd;
wire [2:0] func3;
wire [6:0] func7;
wire [11:0] func12;
wire [3:0] aluop;
wire [2:0] bluop;

bit rwren = 1'b0;
bit [31:0] rdin = 32'd0;
wire [31:0] rval1, rval2;

// ------------------------------------------------------------------------------------
// CSR
// ------------------------------------------------------------------------------------

logic [31:0] CSRReg [0:`CSR_REGISTER_COUNT-1];

// See https://cv32e40p.readthedocs.io/en/latest/control_status_registers/#cs-registers for defaults
initial begin
	CSRReg[`CSR_UNUSED]		= 32'd0;
	CSRReg[`CSR_MSTATUS]	= 32'h00001800; // MPP (machine previous priviledge mode 12:11) hardwired to 2'b11 on startup
	CSRReg[`CSR_MIE]		= 32'd0;
	CSRReg[`CSR_MTVEC]		= 32'd0;
	CSRReg[`CSR_MEPC]		= 32'd0;
	CSRReg[`CSR_MCAUSE]		= 32'd0;
	CSRReg[`CSR_MTVAL]		= 32'd0;
	CSRReg[`CSR_MIP]		= 32'd0;
	CSRReg[`CSR_TIMECMPLO]	= 32'hFFFFFFFF; // timecmp = 0xFFFFFFFFFFFFFFFF
	CSRReg[`CSR_TIMECMPHI]	= 32'hFFFFFFFF;
	CSRReg[`CSR_CYCLELO]	= 32'd0;
	CSRReg[`CSR_CYCLEHI]	= 32'd0;
	CSRReg[`CSR_TIMELO]		= 32'd0;
	CSRReg[`CSR_RETILO]		= 32'd0;
	CSRReg[`CSR_TIMEHI]		= 32'd0;
	CSRReg[`CSR_RETIHI]		= 32'd0;
end

// ------------------------------------------------------------------------------------
// State machine
// ------------------------------------------------------------------------------------

bit [5:0] next_state;
bit [5:0] current_state;

// One bit per state
localparam S_RESET		= 6'd1;
localparam S_RETIRE		= 6'd2;
localparam S_FETCH		= 6'd4;
localparam S_DECODE		= 6'd8;
localparam S_EXEC		= 6'd16;
localparam S_WBACK		= 6'd32;

always @(current_state) begin
	case (current_state)
		S_RESET:	begin next_state = S_RETIRE;		end // Once-only reset state (during device initialization)
		S_RETIRE:	begin next_state = S_FETCH;			end // Kick next instruction fetch, finalize LOAD and register writeback
		S_FETCH:	begin next_state = S_DECODE;		end	// Instruction load delay slot, stall until previous data store is complete
		S_DECODE:	begin next_state = S_EXEC;			end	// Decoder work
		S_EXEC:		begin next_state = S_WBACK;			end	// ALU strobe, bus address calculation and data LOAD kick
		S_WBACK:	begin next_state = S_RETIRE;		end // Set up values for register wb, kick STORE, stall until previous data load is complete
		default:	begin next_state = current_state;	end
	endcase
end

always @(current_state, busaddress, instrOneHot, rval2, func3) begin
	case (current_state)
		S_WBACK: begin
			case ({instrOneHot[`O_H_STORE], func3})
				4'b1_000: begin // 8 bit
					dout = {rval2[7:0], rval2[7:0], rval2[7:0], rval2[7:0]};
					case (busaddress[1:0])
						2'b11: buswe = 4'h8;
						2'b10: buswe = 4'h4;
						2'b01: buswe = 4'h2;
						2'b00: buswe = 4'h1;
					endcase
				end
				4'b1_001: begin // 16 bit
					dout = {rval2[15:0], rval2[15:0]};
					case (busaddress[1])
						1'b1: buswe = 4'hC;
						1'b0: buswe = 4'h3;
					endcase
				end
				4'b1_010: begin // 32 bit
					//dout <= (instrOneHot[`O_H_FLOAT_STW]) ? frval2 : rval2;
					dout = rval2;
					buswe = 4'hF;
				end
				default: begin
					dout = 32'd0;
					buswe = 4'h0;
				end
			endcase
		end
		default: begin
			dout = 32'd0;
			buswe = 4'h0;
		end
	endcase
end

// State transition is actually clocked,
// however the transition logic is combinatorial depending on current_state
always @(posedge cpuclock) begin
	if (reset) begin
		current_state = S_RESET;
	end else begin
		current_state = next_state;
	end
end

// ------------------------------------------------------------------------------------
// Decoder unit
// ------------------------------------------------------------------------------------

decoder InstructionDecoder(
	.enable(decen),								// Hold high for one clock when din is valid to decode
	.instruction(instruction),					// Incoming instruction to decode
	.instrOneHotOut(instrOneHot),				// One-hot form of decoded instruction
	.isrecordingform(isrecordingform),			// High if instruction result should be saved to a register
	.aluop(aluop),								// Arithmetic unit op
	.bluop(bluop),								// Branch unit op
	.func3(func3),								// Sub-function
	.func7(func7),								// Sub-function
	.func12(func12),							// Sub-function
	.rs1(rs1),									// Source register 1
	.rs2(rs2),									// Source register 2
	.rs3(rs3),									// Source register 3 (used for fused operations)
	.rd(rd),									// Destination register
	.csrindex(csrindex),						// CSR register index
	.immed(immed),								// Immediate, converted to 32 bits
	.selectimmedasrval2(selectimmedasrval2) );	// Route to use either immed or value of source register 2 

// ------------------------------------------------------------------------------------
// Register file
// ------------------------------------------------------------------------------------

registerfile IntegerRegisters(
	.clock(cpuclock),
	.rs1(rs1),		// Source register read address
	.rs2(rs2),		// Source register read address
	.rd(rd),		// Destination register write address
	.wren(rwren),	// Write enable for destination register
	.din(rdin),		// Data to write to destination register (written at end of this clock)
	.rval1(rval1),	// Values output from source registers (available on same clock)
	.rval2(rval2) );

// ------------------------------------------------------------------------------------
// ALU / BLU
// ------------------------------------------------------------------------------------

wire [31:0] aluout;

// These instructions require the first operand to be PC and second one to be the immediate
wire reqalu = instrOneHot[`O_H_AUIPC] | instrOneHot[`O_H_JAL] | instrOneHot[`O_H_BRANCH];

arithmeticlogicunit ALU(
	.enable(aluen),											// Hold high to get a result on next clock
	.aluout(aluout),										// Result of calculation
	.func3(func3),											// ALU sub-operation code
	.val1(reqalu ? PC : rval1),								// Input value 1
	.val2((selectimmedasrval2 | reqalu) ? immed : rval2),	// Input value 2
	.aluop(reqalu ? `ALU_ADD : aluop) );					// ALU operation code

wire branchout;

branchlogicunit BLU(
	.branchout(branchout),	// High when branch should be taken based on op
	.val1(rval1),			// Input value 1
	.val2(rval2),			// Input value 2
	.bluop(bluop) );		// Comparison operation code
	
// ------------------------------------------------------------------------------------
// Execution unit
// ------------------------------------------------------------------------------------

always @(posedge cpuclock) begin

	// Signals to clean up at start of each clock
	rwren <= 1'b0;
	busre <= 1'b0;
	decen <= 1'b0;
	aluen <= 1'b0;

	unique case (current_state)
		S_RESET: begin
			PC <= RESETVECTOR;
		end

		S_FETCH: begin
			// Instruction load wait state

			// Pre-read some flags to check during this instruction
			miena <= CSRReg[`CSR_MIE][3];
		end
		
		S_DECODE: begin
			// Instruction load complete, latch it and strobe decoder
			instruction <= din;
			decen <= 1'b1;
		end

		S_EXEC: begin
			// Illegal instruction trap
			illegalinstruction <= (~(|instrOneHot)) & miena;

			// Turn on the ALU for next clock
			aluen <= 1'b1;

			// Calculate bus address for store or load instructions
			if (instrOneHot[`O_H_LOAD] | instrOneHot[`O_H_STORE])
				busaddress <= rval1 + immed;

			// Enable and start reading from memory if we have a load instruction
			busre <= instrOneHot[`O_H_LOAD];
			branchr <= branchout;

			case ({instrOneHot[`O_H_SYSTEM], func3})
				default: begin
					csrval <= 32'd0;
				end
				4'b1_010, // CSRRS
				4'b1_110, // CSRRSI
				4'b1_011, // CSSRRC
				4'b1_111: begin // CSRRCI
					csrval <= CSRReg[csrindex];
				end
			endcase
		end

		S_WBACK: begin
			// NOTE: This is also the data load wait slot for EXEC stage

			unique case (1'b1)
				instrOneHot[`O_H_LUI]:		rdin <= immed;
				instrOneHot[`O_H_JAL],
				instrOneHot[`O_H_JALR],
				instrOneHot[`O_H_BRANCH]:	rdin <= nextPC;
				instrOneHot[`O_H_OP],
				instrOneHot[`O_H_OP_IMM],
				instrOneHot[`O_H_AUIPC]:	rdin <= aluout;
			endcase

			// Set next instruction pointer for exception/interrupts/branches/mret/regular instructions
			if (illegalinstruction) begin
				// Using non-vectored interrupt handlers (last 2 bits are 2'b00)
				PC <= {CSRReg[`CSR_MTVEC][31:2], 2'b00};
				// Save return address for future MRET
				CSRReg[`CSR_MEPC] <= ebreak ? PC : nextPC;
			end else if (mret) begin // MRET returns us to mepc
				PC <= CSRReg[`CSR_MEPC];
			end else begin
				unique case (1'b1)
					instrOneHot[`O_H_JAL]:		PC <= aluout;
					instrOneHot[`O_H_JALR]:		PC <= rval1 + immed;
					instrOneHot[`O_H_BRANCH]:	PC <= branchr ? aluout : nextPC;
					default:					PC <= nextPC;
				endcase
			end

		end

		S_RETIRE: begin

			// Write pending CSR register value
			case ({instrOneHot[`O_H_SYSTEM], func3})
				4'b1_000: begin
					case (func12)
						12'b0000000_00000: begin
							ecall <= miena;
						end
						12'b0000000_00001: begin
							ebreak <= miena;
						end
						12'b0001000_00101: begin
							wfi <= 1'b1;
						end
						12'b0011000_00010: begin
							mret <= 1'b1;
						end
					endcase
				end
				4'b1_001: begin // CSRRW
					CSRReg[csrindex] <= rval1;
				end
				/*4'b1_100: begin
					// ???
				end*/
				4'b1_101: begin // CSRRWI
					CSRReg[csrindex] <= immed;
				end
				4'b1_010: begin // CSRRS
					CSRReg[csrindex] <= csrval | rval1;
				end
				4'b1_110: begin // CSRRSI
					CSRReg[csrindex] <= csrval | immed;
				end
				4'b1_011: begin // CSSRRC
					CSRReg[csrindex] <= csrval & (~rval1);
				end
				4'b1_111: begin // CSRRCI
					CSRReg[csrindex] <= csrval & (~immed);
				end
			endcase

			ecall <= 1'b0;
			ebreak <= 1'b0;
			wfi <= 1'b0;
			mret <= 1'b0;

			// Enable memory reads for next instruction at the next program counter
			busre <= 1'b1;

			busaddress <= PC;
			nextPC <= PC + 32'd4;

			// Store pending loaded word/half/byte in destination register
			if (instrOneHot[`O_H_LOAD]) begin
				case (func3)
					3'b000: begin // BYTE with sign extension
						case (busaddress[1:0])
							2'b11: begin rdin <= {{24{din[31]}}, din[31:24]}; end
							2'b10: begin rdin <= {{24{din[23]}}, din[23:16]}; end
							2'b01: begin rdin <= {{24{din[15]}}, din[15:8]}; end
							2'b00: begin rdin <= {{24{din[7]}},  din[7:0]}; end
						endcase
					end
					3'b001: begin // WORD with sign extension
						case (busaddress[1])
							1'b1: begin rdin <= {{16{din[31]}}, din[31:16]}; end
							1'b0: begin rdin <= {{16{din[15]}}, din[15:0]}; end
						endcase
					end
					3'b010: begin // DWORD
						//if (instrOneHot[`O_H_FLOAT_LDW])
						//	frdin <= din[31:0];
						//else
							rdin <= din[31:0];
					end
					3'b100: begin // BYTE with zero extension
						case (busaddress[1:0])
							2'b11: begin rdin <= {24'd0, din[31:24]}; end
							2'b10: begin rdin <= {24'd0, din[23:16]}; end
							2'b01: begin rdin <= {24'd0, din[15:8]}; end
							2'b00: begin rdin <= {24'd0, din[7:0]}; end
						endcase
					end
					/*3'b101*/ default: begin // WORD with zero extension
						case (busaddress[1])
							1'b1: begin rdin <= {16'd0, din[31:16]}; end
							1'b0: begin rdin <= {16'd0, din[15:0]}; end
						endcase
					end
				endcase
			end

			// Update register value at address rd if this is a recording form instruction
			rwren <= isrecordingform;
		end

	endcase
end

endmodule
