`include "shared.vh"

module cpu
	#(
		parameter RESETVECTOR = 32'h00000000	// Default reset vector, change as required per CPU instance
	)
	(
		input wire cpuclock,
		input wire reset,
		input wire [3:0] irq,
		output bit [31:0] busaddress = 32'd0,	// memory or device address
		input wire [31:0] din,					// data read from memory
		output bit [31:0] dout = 32'd0,			// data to write to memory
		output bit busre = 1'b0,				// memory read enable
		output bit [3:0] buswe = 4'h0,			// memory write enable (byte mask)
		input wire busbusy
	);

// ------------------------------------------------------------------------------------
// Operation
// ------------------------------------------------------------------------------------

// Please see the README.md file for operation details

// ------------------------------------------------------------------------------------
// Internals
// ------------------------------------------------------------------------------------

// Reset vector is in S-RAM
bit [31:0] PC = RESETVECTOR;
bit [31:0] adjacentPC = 32'd0;
bit [31:0] csrval = 32'd0;
bit [31:0] instruction = {25'd0,`OPCODE_OP_IMM,2'b11}; // NOOP (addi x0,x0,0)
bit decen = 1'b0;
bit aluen = 1'b0;
bit branchr = 1'b0;

bit hwinterrupt = 1'b0;
bit illegalinstruction = 1'b0;
bit timerinterrupt = 1'b0;
bit miena = 1'b0;
bit msena = 1'b0;
bit mtena = 1'b0;
bit ecall = 1'b0;
bit ebreak = 1'b0;
bit wfi = 1'b0;
bit mret = 1'b0;
bit trq = 1'b0;
bit [2:0] mip = 3'b000;
bit [31:0] mtvec = 32'd0;

wire isrecordingform;
wire [17:0] instrOneHot;
wire selectimmedasrval2;
wire [31:0] immed;
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
// Timer
// ------------------------------------------------------------------------------------

bit [3:0] shortcnt = 4'h0;
bit [63:0] cpusidetrigger = 64'hFFFFFFFFFFFFFFFF;
bit [63:0] clockcounter = 64'd0;

// Count in cpu clock domain
// The ratio of wall clock to cpu clock is 1/10
// so we can increment this every 10th clock
always @(posedge cpuclock) begin
	shortcnt <= shortcnt + 1;
	if (shortcnt == 9) begin
		shortcnt <= 0;
		clockcounter <= clockcounter + 64'd1;
	end
	trq <= (clockcounter >= cpusidetrigger) ? 1'b1 : 1'b0;
end

// ------------------------------------------------------------------------------------
// CSR
// ------------------------------------------------------------------------------------

logic [31:0] CSRReg [0:`CSR_REGISTER_COUNT-1];
wire [4:0] csrindex;
bit csrwe = 1'b0;
bit [31:0] csrin = 32'd0;
bit [4:0] csrindex_l;

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

bit [8:0] next_state;
bit [8:0] current_state;

// One bit per state
localparam S_RESET			= 9'd1;
localparam S_RETIRE			= 9'd2;
localparam S_FETCH			= 9'd4;
localparam S_DECODE			= 9'd8;
localparam S_EXEC			= 9'd16;
localparam S_WBACK			= 9'd32;
localparam S_LOADWAIT		= 9'd64;
localparam S_INTERRUPTWAIT	= 9'd128;
localparam S_STOREWAIT		= 9'd256;

always_comb begin
	case (current_state)
		S_RESET:			next_state = S_RETIRE;
		S_RETIRE:			next_state = S_FETCH;
		S_FETCH:			next_state = S_DECODE;
		S_DECODE:			next_state = S_EXEC;
		S_EXEC:				next_state = instrOneHot[`O_H_LOAD] ? S_LOADWAIT : S_WBACK;
		S_LOADWAIT:			next_state = busbusy ? S_LOADWAIT : S_WBACK;
		S_WBACK:			next_state = wfi ? S_INTERRUPTWAIT : (instrOneHot[`O_H_STORE] ? S_STOREWAIT : S_RETIRE);
		S_STOREWAIT:		next_state = busbusy ? S_STOREWAIT : S_RETIRE;
		S_INTERRUPTWAIT:	next_state = (hwinterrupt | timerinterrupt) ? S_RETIRE : S_INTERRUPTWAIT;
		default:			next_state = current_state;
	endcase
end

always_comb begin
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

always_comb begin
	case (current_state)
		S_EXEC: begin
			ecall = 1'b0;
			ebreak = 1'b0;
			wfi = 1'b0;
			mret = 1'b0;
			if ({instrOneHot[`O_H_SYSTEM], func3} == 4'b1_000) begin
				case (func12)
					12'b0000000_00000: begin	// Sys call
						ecall = msena;
					end
					12'b0000000_00001: begin	// Software breakpoint
						ebreak = msena;
					end
					12'b0001000_00101: begin	// Wait for interrupt
						wfi = miena | msena | mtena;	// Use individual interrupt enable bits, ignore global interrupt enable
					end
					12'b0011000_00010: begin	// Return from interrupt
						mret = 1'b1;
					end
					default: begin
						//
					end
				endcase
			end
		end
		default: begin
			//
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
	.aluop(reqalu ? `ALU_ADD : aluop) );					// ALU operation code (also ADD for JALR for rval1+immed)

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
	csrwe <= 1'b0;

	unique case (current_state)
		S_RESET: begin
			PC <= RESETVECTOR;
		end

		S_FETCH: begin
			// Instruction load wait slot

			// Set up adjacent PC
			adjacentPC <= PC + 32'd4;

			// Pre-read some registers to check during this instruction
			// TODO: Only need to update these when they're changed, move to a separate stage post-CSR-write
			{miena, msena, mtena} <= {CSRReg[`CSR_MIE][11], CSRReg[`CSR_MIE][3], CSRReg[`CSR_MIE][7]}; // interrupt enable state
			mtvec <= {CSRReg[`CSR_MTVEC][31:2], 2'b00};
			mip <= {CSRReg[`CSR_MIP][11], CSRReg[`CSR_MIP][3], CSRReg[`CSR_MIP][7]}; // high if interrupt pending
			cpusidetrigger <= {CSRReg[`CSR_TIMECMPHI], CSRReg[`CSR_TIMECMPLO]}; // Latch the timecmp value
		end

		S_DECODE: begin
			// Instruction load complete, latch it and strobe decoder
			instruction <= din;
			decen <= 1'b1;

			// Update clock
			CSRReg[`CSR_TIMEHI] <= clockcounter[63:32];
			CSRReg[`CSR_TIMELO] <= clockcounter[31:0];
		end

		S_EXEC: begin
			// Set traps only if respective trap bit is set and we're not already handling a trap
			// This prevents re-entrancy in trap handlers.
			hwinterrupt <= (|irq) & miena & (~(|mip));
			illegalinstruction <= (~(|instrOneHot)) & msena & (~(|mip));
			timerinterrupt <= trq & mtena & (~(|mip));

			// Turn on the ALU for next clock
			aluen <= 1'b1;

			// Calculate bus address for store or load instructions
			if (instrOneHot[`O_H_LOAD] | instrOneHot[`O_H_STORE])
				busaddress <= rval1 + immed;

			// Enable and start reading from memory if we have a load instruction
			busre <= instrOneHot[`O_H_LOAD];

			// Store branch result
			branchr <= branchout;

			csrindex_l <= csrindex;
			case ({instrOneHot[`O_H_SYSTEM], func3})
				4'b1_010, // CSRRS
				4'b1_110, // CSRRSI
				4'b1_011, // CSSRRC
				4'b1_111: begin // CSRRCI
					csrval <= CSRReg[csrindex];
				end
				default: begin
					csrval <= 32'd0;
				end
			endcase
		end

		S_LOADWAIT: begin
			// data load wait slot
		end
		
		S_INTERRUPTWAIT: begin
			// We do not need to check for illegal instruction as that can't happen
			// during this instruction, which is already being executed and in the lead.
			hwinterrupt <= (|irq) & miena & (~(|mip));
			timerinterrupt <= trq & mtena & (~(|mip));
		end

		S_WBACK: begin
			case (1'b1)
				/*instrOneHot[`O_H_LUI]*/
				default:					rdin <= immed;
				instrOneHot[`O_H_JAL],
				instrOneHot[`O_H_JALR],
				instrOneHot[`O_H_BRANCH]:	rdin <= adjacentPC;
				instrOneHot[`O_H_OP],
				instrOneHot[`O_H_OP_IMM],
				instrOneHot[`O_H_AUIPC]:	rdin <= aluout;
				instrOneHot[`O_H_SYSTEM]: begin
					rdin <= csrval;
					csrin <= csrval;
					csrwe <= 1'b1;
					case(func3)
						/*3'b000*/ default: begin
							csrwe <= 1'b0;
						end
						3'b001: begin // CSRRW
							csrin <= rval1;
						end
						3'b101: begin // CSRRWI
							csrin <= immed;
						end
						3'b010: begin // CSRRS
							csrin <= csrval | rval1;
						end
						3'b110: begin // CSRRSI
							csrin <= csrval | immed;
						end
						3'b011: begin // CSSRRC
							csrin <= csrval & (~rval1);
						end
						3'b111: begin // CSRRCI
							csrin <= csrval & (~immed);
						end
					endcase
				end
				instrOneHot[`O_H_LOAD]: begin
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
			endcase

			// Update register value at address rd if this is a recording form instruction
			rwren <= isrecordingform;

			if (mret) begin // MRET returns us to mepc
				PC <= CSRReg[`CSR_MEPC];
				// Clear handled bit with correct priority
				if (mip[2])
					CSRReg[`CSR_MIP][11] <= 1'b0;
				else if(mip[1])
					CSRReg[`CSR_MIP][3] <= 1'b0;
				else if(mip[0])
					CSRReg[`CSR_MIP][7] <= 1'b0;
			end else if (ecall) begin
				// TODO:
			end else if (ebreak) begin
				// Keep PC on same address, we'll be repeating this instuction
				// until software overwrites it with something else
				//PC <= PC;
			end else begin
				case (1'b1)
					instrOneHot[`O_H_JAL],
					instrOneHot[`O_H_JALR]:		PC <= aluout;
					instrOneHot[`O_H_BRANCH]:	PC <= branchr ? aluout : adjacentPC;
					default:					PC <= adjacentPC;
				endcase
			end
		end

		S_RETIRE: begin
			// Write back to CSR register file
			if (csrwe)
				CSRReg[csrindex_l] <= csrin;

			// Ordering according to privileged ISA is: mei/msi/mti/sei/ssi/sti
			if (hwinterrupt) begin // mei, external hardware interrupt
				// Using non-vectored interrupt handlers (last 2 bits are 2'b00)
				CSRReg[`CSR_MIP][11] <= 1'b1;
				CSRReg[`CSR_MEPC] <= PC;
				CSRReg[`CSR_MTVAL] <= {28'd0, irq}; // Interrupting hardware selector
				CSRReg[`CSR_MCAUSE] <= 32'h8000000B; // [31]=1'b1(interrupt), 11->h/w
			end else if (illegalinstruction) begin // msi, exception
				// Using non-vectored interrupt handlers (last 2 bits are 2'b00)
				CSRReg[`CSR_MIP][3] <= 1'b1;
				CSRReg[`CSR_MEPC] <= PC;
				CSRReg[`CSR_MTVAL] <= instruction;
				CSRReg[`CSR_MCAUSE] <= 32'h00000002; // [31]=1'b0(exception), 2->illegal instruction
			end else if (timerinterrupt) begin // mti, timer interrupt
				CSRReg[`CSR_MIP][7] <= 1'b1;
				CSRReg[`CSR_MEPC] <= PC;
				CSRReg[`CSR_MTVAL] <= 32'd0;
				CSRReg[`CSR_MCAUSE] <= 32'h80000007; // [31]=1'b1(interrupt), 7->timer
			end

			// Enable memory reads for next instruction at the new program counter or interrupt vector
			busre <= 1'b1;
			if (hwinterrupt | illegalinstruction | timerinterrupt) begin
				PC <= mtvec;
				busaddress <= mtvec;
			end else begin
				busaddress <= PC;
			end
		end

	endcase
end

endmodule
