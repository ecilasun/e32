`timescale 1ns / 1ps

`include "shared.vh"

module cpu
	#(
		parameter RESETVECTOR = 32'h00000000	// Default reset vector, change as required per CPU instance
	)
	(
		input wire cpuclock,
		input wire reset,
		input wire irqtrigger,
		input [3:0] irqlines,
		output bit [31:0] busaddress = 32'd0,	// memory or device address
		input wire [31:0] din,					// data read from memory
		output bit [31:0] dout = 32'd0,			// data to write to memory
		output bit busre = 1'b0,				// memory read enable
		output bit [3:0] buswe = 4'h0,			// memory write enable (byte mask)
		input wire busbusy						// high when bus busy after r/w request
	);

// ------------------------------------------------------------------------------------
// Operation
// ------------------------------------------------------------------------------------

// State:			RESET					RETIRE						FETCH							EXEC							WBACK
//
// Work done:		Once at startup			Sets up register			Instruction read delay			Sets up LOAD/STORE bus			Calculates write back values
//			 		sets up default			write values and			slot, enables decoder.			address, enables read			and sets up bus write enable for
//					machine states.			write enable, sets											for LOAD and sets next PC.		STORE.
//											up next instruction
//											read.
//
// Next state:		RETIRE					FETCH						EXEC							WBACK							RETIRE

// ------------------------------------------------------------------------------------
// Internals
// ------------------------------------------------------------------------------------

// Reset vector is in S-RAM
bit [31:0] PC = RESETVECTOR;
bit [31:0] nextPC = 32'd0;
bit [31:0] instruction = {25'd0,`OPCODE_OP_IMM,2'b11}; // NOOP (addi x0,x0,0)
bit decen = 1'b0;
bit aluen = 1'b0;

// ------------------------------------------------------------------------------------
// State machine
// ------------------------------------------------------------------------------------

bit [5:0] next_state;
bit [5:0] current_state;

// One bit per state
localparam S_RESET = 6'd1;
localparam S_FETCH = 6'd2;
localparam S_DECODE = 6'd4;
localparam S_EXEC  = 6'd8;
localparam S_WBACK = 6'd16;
localparam S_RETIRE = 6'd32;

always @(current_state, busbusy) begin
	case (current_state)
		S_RESET:	begin next_state = S_RETIRE;						end // Once-only reset state (during device initialization)
		S_RETIRE:	begin next_state = busbusy ? S_RETIRE : S_FETCH;	end // Kick next instruction fetch, finalize LOAD & register wb (NOTE: Mem read here; if busbusy!=1'b0, stall?)
		S_FETCH:	begin next_state = S_DECODE;						end	// Instruction load delay slot
		S_DECODE:	begin next_state = S_EXEC;							end	// Decoder work
		S_EXEC:		begin next_state = busbusy ? S_EXEC : S_WBACK;		end	// ALU strobe (NOTE: Mem read here; if busbusy!=1'b0, stall?)
		S_WBACK:	begin next_state = busbusy ? S_WBACK : S_RETIRE;	end // Set up values for register wb, kick STORE (NOTE: Mem write here; if busbusy!=1'b0, stall?)
		default:	begin next_state = current_state;					end
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

wire isrecordingform;
wire [18:0] instrOneHot;
wire illlegalInstruction;
wire selectimmedasrval2;
wire [31:0] immed;
wire [4:0] csrindex;
wire [4:0] rs1, rs2, rs3, rd;
wire [2:0] func3;
wire [6:0] func7;
wire [11:0] func12;
wire [3:0] aluop;
wire [2:0] bluop;

decoder InstructionDecoder(
	.enable(decen),								// Hold high for one clock when din is valid to decode
	.instruction(instruction),					// Incoming instruction to decode
	.instrOneHotOut(instrOneHot),				// One-hot form of decoded instruction
	.isrecordingform(isrecordingform),			// High if instruction result should be saved to a register
	.decie(illlegalInstruction),				// High if instruction cannot be decoded
	.aluop(aluop),								// Arithmetic unit op
	.bluop(bluop),								// Branch unit op
	.func3(func3),								// Sub-function
	.func7(func7),								// Sub-function
	.func12(func12),							// Sub-function
	.rs1(rs1),									// Source register 1
	.rs2(rs2),									// Source register 2
	.rs3(rs3),									// Source register 3 (used for fused operations)
	.rd(rd),									// Destination register
	.csrindex(csrindex),						// CSR register address to CSR register file index
	.immed(immed),								// Immediate, converted to 32 bits
	.selectimmedasrval2(selectimmedasrval2) );	// Route to use either immed or value of source register 2 

// ------------------------------------------------------------------------------------
// Register file
// ------------------------------------------------------------------------------------

bit rwren = 1'b0;
bit [31:0] rdin = 32'd0, wback = 32'd0;
wire [31:0] rval1, rval2;

// Register file
// Writes happen after reads to avoid overwriting and losing existing values
// in the same address.
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
	buswe <= 4'h0;
	busre <= 1'b0;
	decen <= 1'b0;
	aluen <= 1'b0;

	unique case (current_state)
		S_RESET: begin
			PC <= RESETVECTOR;
		end

		S_FETCH: begin
			// TODO: Load time compare and other machine control states from CSR registers
			// TODO: Check for any pending interrupt from the IRQ bits and set up for later
		end
		
		S_DECODE: begin
			instruction <= din;
			decen <= 1'b1;
		end

		S_EXEC: begin
			// Turn on the ALU for next clock
			aluen <= 1'b1;
			// Calculate bus address for store or load instructions
			if (instrOneHot[`O_H_LOAD] | instrOneHot[`O_H_STORE])
				busaddress <= rval1 + immed;
			// Enable and start reading from memory if we have a load instruction
			busre <= instrOneHot[`O_H_LOAD];
		end

		S_WBACK: begin
			unique case (1'b1)
				// Properly cull/wrap the register value 2 and write to memory
				// Since it's either a load or a store on one instruction,
				// we don't need to care about any clashes with the EXEC state's busre signal (which will be low when STORE==1)
				instrOneHot[`O_H_STORE]: begin
					case (func3)
						3'b000: begin // 8bit
							dout <= {rval2[7:0], rval2[7:0], rval2[7:0], rval2[7:0]};
							// Alternatively, following could be: buswe <= 4'h1 << busaddress[1:0];
							case (busaddress[1:0])
								2'b11: buswe <= 4'h8;
								2'b10: buswe <= 4'h4;
								2'b01: buswe <= 4'h2;
								2'b00: buswe <= 4'h1;
							endcase
						end
						3'b001: begin // 16bit
							dout <= {rval2[15:0], rval2[15:0]};
							// Alternatively, following could be: buswe <= 4'h3 << {busaddress[1],1'b0};
							case (busaddress[1])
								1'b1: buswe <= 4'hC;
								1'b0: buswe <= 4'h3;
							endcase
						end
						/*3'b010*/ default: begin // 32bit
							//dout <= (instrOneHot[`O_H_FLOAT_STW]) ? frval2 : rval2;
							dout <= rval2;
							buswe <= 4'hF;
						end
					endcase
				end
				// For the rest, writes go to a register (temporarily held in wback)
				instrOneHot[`O_H_LUI]:		wback <= immed;
				instrOneHot[`O_H_JAL],
				instrOneHot[`O_H_JALR],
				instrOneHot[`O_H_BRANCH]:	wback <= nextPC;
				instrOneHot[`O_H_OP],
				instrOneHot[`O_H_OP_IMM],
				instrOneHot[`O_H_AUIPC]:	wback <= aluout;
			endcase

			// Set next instruction pointer for branches or regular instructions
			unique case (1'b1)
				instrOneHot[`O_H_JAL]:		PC <= aluout;
				instrOneHot[`O_H_JALR]:		PC <= rval1 + immed;
				instrOneHot[`O_H_BRANCH]:	PC <= branchout ? aluout : nextPC;
				default:					PC <= nextPC;
			endcase

			// TODO: Route PC to handle interrupts (irqtrigger/irqlines) or exceptions (illegal instruction/ebreak/syscall etc) when an IRQ/exception occurs

			// TODO: Write back modified contents of CSR registers
		end

		S_RETIRE: begin
			// Enable memory reads for next instruction at the next program counter
			busre <= 1'b1;
			busaddress <= PC;
			nextPC <= PC + 32'd4;

			if (instrOneHot[`O_H_LOAD]) begin
				// Write sign or zero extended data from load operation to register
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
			end else begin
				// For all other cases, write previously generated writeback value to register
				// NOTE: STORE will not really write this value (see rwen below) but we need
				// to fill both sides of the if statement for shorter logic.
				rdin <= wback;
			end

			// Update register value at address rd if this is a recording form instruction
			rwren <= isrecordingform;
		end

	endcase
end

endmodule
