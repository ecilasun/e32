`timescale 1ns / 1ps

`include "shared.vh"

module axi4cpu #(
	parameter RESETVECTOR=32'h00000000 ) (
	axi4 axi4if,
	input wire [3:0] irq );

// CPU states
localparam CPUINIT = 1;
localparam CPURETIRE = 2;
localparam CPUFETCH = 4;
localparam CPUDECODE = 8;
localparam CPUEXECUTE = 16;
localparam CPULOADWAIT = 32;
localparam CPUSTOREWAIT = 64;
localparam CPUIMATHWAIT = 128;
localparam CPUFMSTALL = 256;
localparam CPUFPUOP = 512;
localparam CPUFSTALL = 1024;
localparam CPUWBACK = 2048;
localparam CPUWFI = 4096;

logic [12:0] cpustate = CPUINIT;
logic [31:0] PC = RESETVECTOR;
logic [31:0] adjacentPC = RESETVECTOR + 32'd4;
logic [31:0] csrval = 32'd0;

logic hwinterrupt = 1'b0;
logic illegalinstruction = 1'b0;
logic timerinterrupt = 1'b0;
logic miena = 1'b0;
logic msena = 1'b0;
logic mtena = 1'b0;
logic ecall = 1'b0;
logic ebreak = 1'b0;
logic wfi = 1'b0;
logic mret = 1'b0;
logic trq = 1'b0;
logic [2:0] mip = 3'b000;
logic [31:0] mtvec = 32'd0;

// ------------------------------------------------------------------------------------
// Timer unit
// ------------------------------------------------------------------------------------

logic [3:0] shortcnt = 4'h0;
logic [63:0] cpusidetrigger = 64'hFFFFFFFFFFFFFFFF;
logic [63:0] clockcounter = 64'd0;

// Count in cpu clock domain
// The ratio of wall clock to cpu clock is 1/10
// so we can increment this every 10th clock
always @(posedge axi4if.ACLK) begin
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
// Decoder unit
// ------------------------------------------------------------------------------------

bit [31:0] instruction = {25'd0,`OPCODE_OP_IMM,2'b11}; // NOOP (addi x0,x0,0)
bit decen = 1'b0;

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
// Register files
// ------------------------------------------------------------------------------------

logic rwren = 1'b0;
logic frwe = 1'b0;
logic [31:0] rdin = 32'd0;
logic [31:0] frdin = 32'd0;
wire [31:0] rval1, rval2;
wire [31:0] frval1, frval2, frval3;

registerfile IntegerRegisters(
	.clock(axi4if.ACLK),
	.rs1(rs1),		// Source register read address
	.rs2(rs2),		// Source register read address
	.rd(rd),		// Destination register write address
	.wren(rwren),	// Write enable for destination register
	.din(rdin),		// Data to write to destination register (written at end of this clock)
	.rval1(rval1),	// Values output from source registers (available on same clock)
	.rval2(rval2) );

// Floating point register file
floatregisterfile FloatRegisters(
	.clock(axi4if.ACLK),
	.rs1(rs1),
	.rs2(rs2),
	.rs3(rs3),
	.rd(rd),
	.wren(frwe),
	.datain(frdin),
	.rval1(frval1),
	.rval2(frval2),
	.rval3(frval3) );

// ------------------------------------------------------------------------------------
// ALU / BLU
// ------------------------------------------------------------------------------------

bit aluen = 1'b0;
wire reqalu = instrOneHot[`O_H_AUIPC] | instrOneHot[`O_H_JAL] | instrOneHot[`O_H_BRANCH]; // These instructions require the first operand to be PC and second one to be the immediate

wire [31:0] aluout;

arithmeticlogicunit ALU(
	.enable(aluen),											// Hold high to get a result on next clock
	.aluout(aluout),										// Result of calculation
	.func3(func3),											// ALU sub-operation code
	.val1(reqalu ? PC : rval1),								// Input value 1
	.val2((selectimmedasrval2 | reqalu) ? immed : rval2),	// Input value 2
	.aluop(reqalu ? `ALU_ADD : aluop) );					// ALU operation code (also ADD for JALR for rval1+immed)

wire branchout;
bit branchr = 1'b0;

branchlogicunit BLU(
	.branchout(branchout),	// High when branch should be taken based on op
	.val1(rval1),			// Input value 1
	.val2(rval2),			// Input value 2
	.bluop(bluop) );		// Comparison operation code

// -----------------------------------------------------------------------
// FPU
// -----------------------------------------------------------------------

logic fmaddstrobe = 1'b0;
logic fmsubstrobe = 1'b0;
logic fnmsubstrobe = 1'b0;
logic fnmaddstrobe = 1'b0;
logic faddstrobe = 1'b0;
logic fsubstrobe = 1'b0;
logic fmulstrobe = 1'b0;
logic fdivstrobe = 1'b0;
logic fi2fstrobe = 1'b0;
logic fui2fstrobe = 1'b0;
logic ff2istrobe = 1'b0;
logic ff2uistrobe = 1'b0;
logic fsqrtstrobe = 1'b0;
logic feqstrobe = 1'b0;
logic fltstrobe = 1'b0;
logic flestrobe = 1'b0;

wire FPUResultValid;
wire [31:0] FPUResult;

FPU FloatingPointMathUnit(
	.clock(axi4if.ACLK),

	// Inputs
	.frval1(frval1),
	.frval2(frval2),
	.frval3(frval3),
	.rval1(rval1), // i2f input

	// Operation select strobe
	.fmaddstrobe(fmaddstrobe),
	.fmsubstrobe(fmsubstrobe),
	.fnmsubstrobe(fnmsubstrobe),
	.fnmaddstrobe(fnmaddstrobe),
	.faddstrobe(faddstrobe),
	.fsubstrobe(fsubstrobe),
	.fmulstrobe(fmulstrobe),
	.fdivstrobe(fdivstrobe),
	.fi2fstrobe(fi2fstrobe),
	.fui2fstrobe(fui2fstrobe),
	.ff2istrobe(ff2istrobe),
	.ff2uistrobe(ff2uistrobe),
	.fsqrtstrobe(fsqrtstrobe),
	.feqstrobe(feqstrobe),
	.fltstrobe(fltstrobe),
	.flestrobe(flestrobe),

	// Output
	.resultvalid(FPUResultValid),
	.result(FPUResult) );

// -----------------------------------------------------------------------
// Integer math (mul/div)
// -----------------------------------------------------------------------

logic [31:0] mout = 32'd0;
logic mwrite = 1'b0;

wire mulbusy, divbusy, divbusyu;
wire [31:0] product;
wire [31:0] quotient;
wire [31:0] quotientu;
wire [31:0] remainder;
wire [31:0] remainderu;

wire isexecuting = (cpustate==CPUEXECUTE);
wire isexecutingimath = isexecuting & instrOneHot[`O_H_OP];
//wire isexecutingfloatop = isexecuting & instrOneHot[`O_H_FLOAT_OP];

// Pulses to kick math operations
wire mulstart = isexecutingimath & (aluop==`ALU_MUL);
multiplier themul(
    .clk(axi4if.ACLK),
    .reset(~axi4if.ARESETn),
    .start(mulstart),
    .busy(mulbusy),           // calculation in progress
    .func3(func3),
    .multiplicand(rval1),
    .multiplier(rval2),
    .product(product) );

wire divstart = isexecutingimath & (aluop==`ALU_DIV | aluop==`ALU_REM);
DIVU unsigneddivider (
	.clk(axi4if.ACLK),
	.reset(~axi4if.ARESETn),
	.start(divstart),		// start signal
	.busy(divbusyu),		// calculation in progress
	.dividend(rval1),		// dividend
	.divisor(rval2),		// divisor
	.quotient(quotientu),	// result: quotient
	.remainder(remainderu)	// result: remainer
);

DIV signeddivider (
	.clk(axi4if.ACLK),
	.reset(~axi4if.ARESETn),
	.start(divstart),		// start signal
	.busy(divbusy),			// calculation in progress
	.dividend(rval1),		// dividend
	.divisor(rval2),		// divisor
	.quotient(quotient),	// result: quotient
	.remainder(remainder)	// result: remainder
);

// Stall status
wire imathstart = divstart | mulstart;
wire imathbusy = divbusy | divbusyu | mulbusy;

// ------------------------------------------------------------------------------------
// CPU
// ------------------------------------------------------------------------------------

bit [31:0] baseaddress = 32'd0;

always @(posedge axi4if.ACLK) begin
	decen <= 1'b0;
	aluen <= 1'b0;
	rwren <= 1'b0;
	csrwe <= 1'b0;
	mwrite <= 1'd0;
	frwe <= 1'b0;

	case (cpustate)
		CPUINIT: begin
			PC <= RESETVECTOR;
			if (~axi4if.ARESETn)
				cpustate <= CPUINIT;
			else begin
				cpustate <= CPURETIRE;
			end
		end

		CPUWFI: begin
			hwinterrupt <= (|irq) & miena & (~(|mip));
			timerinterrupt <= trq & mtena & (~(|mip));

			if (hwinterrupt | timerinterrupt) begin
				cpustate <= CPURETIRE;
			end else begin
				cpustate <= CPUWFI;
			end
		end

		CPURETIRE: begin
			// Write back to CSR register file
			if (csrwe)
				CSRReg[csrindex_l] <= csrin;

			// Ordering according to privileged ISA is: mei/msi/mti/sei/ssi/sti
			if (hwinterrupt) begin // mei, external hardware interrupt
				// Using non-vectored interrupt handlers (last 2 bits are 2'b00)
				CSRReg[`CSR_MIP][11] <= 1'b1;
				CSRReg[`CSR_MEPC] <= adjacentPC;
				CSRReg[`CSR_MTVAL] <= {28'd0, irq}; // Interrupting hardware selector
				CSRReg[`CSR_MCAUSE] <= 32'h8000000B; // [31]=1'b1(interrupt), 11->h/w
			end else if (illegalinstruction) begin // msi, exception
				// Using non-vectored interrupt handlers (last 2 bits are 2'b00)
				CSRReg[`CSR_MIP][3] <= 1'b1;
				CSRReg[`CSR_MEPC] <= adjacentPC;
				CSRReg[`CSR_MTVAL] <= instruction;
				CSRReg[`CSR_MCAUSE] <= 32'h00000002; // [31]=1'b0(exception), 2->illegal instruction
			end else if (timerinterrupt) begin // mti, timer interrupt
				CSRReg[`CSR_MIP][7] <= 1'b1;
				CSRReg[`CSR_MEPC] <= adjacentPC;
				CSRReg[`CSR_MTVAL] <= 32'd0;
				CSRReg[`CSR_MCAUSE] <= 32'h80000007; // [31]=1'b1(interrupt), 7->timer
			end

			// Point at the current instruction address based on IRQ status
			if (hwinterrupt | illegalinstruction | timerinterrupt) begin
				PC <= mtvec;
				axi4if.ARADDR <= mtvec;
			end else begin
				axi4if.ARADDR <= PC;
			end

			axi4if.ARVALID <= 1'b1;
			axi4if.RREADY <= 1'b1; // Ready to accept

			if (axi4if.ARREADY) begin
				cpustate <= CPUFETCH;
			end else begin
				cpustate <= CPURETIRE;
			end
		end

		CPUFETCH: begin
			axi4if.ARVALID <= 1'b0;
			
			if (axi4if.RVALID) begin
				axi4if.RREADY <= 1'b0; // Data accepted, and won't accept further

				// Latch instruction and enable decoder
				instruction <= axi4if.RDATA;
				decen <= 1'b1;
				// This is to be used at later stages
				adjacentPC <= PC + 32'd4;

				// Pre-read some registers to check during this instruction
				// TODO: Only need to update these when they're changed, move to a separate stage post-CSR-write
				{miena, msena, mtena} <= {CSRReg[`CSR_MIE][11], CSRReg[`CSR_MIE][3], CSRReg[`CSR_MIE][7]}; // interrupt enable state
				mtvec <= {CSRReg[`CSR_MTVEC][31:2], 2'b00};
				mip <= {CSRReg[`CSR_MIP][11], CSRReg[`CSR_MIP][3], CSRReg[`CSR_MIP][7]}; // high if interrupt pending
				cpusidetrigger <= {CSRReg[`CSR_TIMECMPHI], CSRReg[`CSR_TIMECMPLO]}; // Latch the timecmp value

				cpustate <= CPUDECODE;
			end else begin

				cpustate <= CPUFETCH;
			end
		end

		CPUDECODE: begin
			aluen <= 1'b1;

			// Calculate base address for possible LOAD and STORE instructions
			baseaddress <= rval1 + immed;

			// Latch branch decision
			branchr <= branchout;

			// Update clock
			CSRReg[`CSR_TIMEHI] <= clockcounter[63:32];
			CSRReg[`CSR_TIMELO] <= clockcounter[31:0];

			cpustate <= CPUEXECUTE;
		end

		CPUEXECUTE: begin
			// System operations
			ecall <= 1'b0;
			ebreak <= 1'b0;
			wfi <= 1'b0;
			mret <= 1'b0;

			// Set traps only if respective trap bit is set and we're not already handling a trap
			// This prevents re-entrancy in trap handlers.
			hwinterrupt <= (|irq) & miena & (~(|mip));
			illegalinstruction <= (~(|instrOneHot)) & msena & (~(|mip));
			timerinterrupt <= trq & mtena & (~(|mip));

			// LOAD
			if (instrOneHot[`O_H_FLOAT_MADD] || instrOneHot[`O_H_FLOAT_MSUB] || instrOneHot[`O_H_FLOAT_NMSUB] || instrOneHot[`O_H_FLOAT_NMADD]) begin
				// Fused FPU operations
				fmaddstrobe <= instrOneHot[`O_H_FLOAT_MADD];
				fmsubstrobe <= instrOneHot[`O_H_FLOAT_MSUB];
				fnmsubstrobe <= instrOneHot[`O_H_FLOAT_NMSUB];
				fnmaddstrobe <= instrOneHot[`O_H_FLOAT_NMADD];
				cpustate <= CPUFMSTALL;
			end else if (instrOneHot[`O_H_FLOAT_OP]) begin
				// Regular FPU operations
				cpustate <= CPUFPUOP;
			end else if (instrOneHot[`O_H_LOAD] | instrOneHot[`O_H_FLOAT_LDW]) begin
				// Set up address for load
				axi4if.ARADDR <= baseaddress;
				axi4if.ARVALID <= 1'b1;
				axi4if.RREADY <= 1'b1; // Ready to accept
				if (axi4if.ARREADY) begin // Wait until bus accepts the read address
					cpustate <= CPULOADWAIT;
				end else begin
					cpustate <= CPUEXECUTE;
				end
			end else if (instrOneHot[`O_H_STORE] | instrOneHot[`O_H_FLOAT_STW]) begin // STORE
				// Set up address for store...
				axi4if.AWADDR <= baseaddress;
				axi4if.AWVALID <= 1'b1;

				// ...while also driving the data output and also assert ready
				axi4if.WVALID <= 1'b1;

				// Ready for a response
				axi4if.BREADY <= 1'b1;

				// Byte selection/replication based on target address
				case (func3)
					3'b000: begin // 8 bit
						axi4if.WDATA <= {rval2[7:0], rval2[7:0], rval2[7:0], rval2[7:0]};
						case (baseaddress[1:0])
							2'b11: axi4if.WSTRB <= 4'h8;
							2'b10: axi4if.WSTRB <= 4'h4;
							2'b01: axi4if.WSTRB <= 4'h2;
							2'b00: axi4if.WSTRB <= 4'h1;
						endcase
					end
					3'b001: begin // 16 bit
						axi4if.WDATA <= {rval2[15:0], rval2[15:0]};
						case (baseaddress[1])
							1'b1: axi4if.WSTRB <= 4'hC;
							1'b0: axi4if.WSTRB <= 4'h3;
						endcase
					end
					3'b010: begin // 32 bit
						axi4if.WDATA <= (instrOneHot[`O_H_FLOAT_STW]) ? frval2 : rval2;
						axi4if.WSTRB <= 4'hF;
					end
					default: begin
						axi4if.WDATA <= 32'd0;
						axi4if.WSTRB <= 4'h0;
					end
				endcase
				cpustate <= CPUSTOREWAIT;
			end else if (imathstart) begin
				// Interger math operation pending
				cpustate <= CPUIMATHWAIT;
			end else begin
				case ({instrOneHot[`O_H_SYSTEM], func3})
					4'b1_000: begin // SYS
						case (func12)
							12'b0000000_00000: begin	// Sys call
								ecall <= msena;
							end
							12'b0000000_00001: begin	// Software breakpoint
								ebreak <= msena;
							end
							12'b0001000_00101: begin	// Wait for interrupt
								wfi <= miena | msena | mtena;	// Use individual interrupt enable bits, ignore global interrupt enable
							end
							12'b0011000_00010: begin	// Return from interrupt
								mret <= 1'b1;
							end
							default: begin
								//
							end
						endcase
					end
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
				cpustate <= CPUWBACK;
			end
		end

		CPULOADWAIT: begin
			axi4if.ARVALID <= 1'b0;

			if (axi4if.RVALID) begin
				axi4if.RREADY <= 1'b0; // Data accepted, go to not-ready

				case (func3)
					3'b000: begin // BYTE with sign extension
						case (baseaddress[1:0])
							2'b11: begin rdin <= {{24{axi4if.RDATA[31]}}, axi4if.RDATA[31:24]}; end
							2'b10: begin rdin <= {{24{axi4if.RDATA[23]}}, axi4if.RDATA[23:16]}; end
							2'b01: begin rdin <= {{24{axi4if.RDATA[15]}}, axi4if.RDATA[15:8]}; end
							2'b00: begin rdin <= {{24{axi4if.RDATA[7]}},  axi4if.RDATA[7:0]}; end
						endcase
					end
					3'b001: begin // WORD with sign extension
						case (baseaddress[1])
							1'b1: begin rdin <= {{16{axi4if.RDATA[31]}}, axi4if.RDATA[31:16]}; end
							1'b0: begin rdin <= {{16{axi4if.RDATA[15]}}, axi4if.RDATA[15:0]}; end
						endcase
					end
					3'b010: begin // DWORD
						if (instrOneHot[`O_H_FLOAT_LDW]) begin
							frwe <= 1'b1;
							frdin <= axi4if.RDATA[31:0];
						end else begin
							rdin <= axi4if.RDATA[31:0];
						end
					end
					3'b100: begin // BYTE with zero extension
						case (baseaddress[1:0])
							2'b11: begin rdin <= {24'd0, axi4if.RDATA[31:24]}; end
							2'b10: begin rdin <= {24'd0, axi4if.RDATA[23:16]}; end
							2'b01: begin rdin <= {24'd0, axi4if.RDATA[15:8]}; end
							2'b00: begin rdin <= {24'd0, axi4if.RDATA[7:0]}; end
						endcase
					end
					/*3'b101*/ default: begin // WORD with zero extension
						case (baseaddress[1])
							1'b1: begin rdin <= {16'd0, axi4if.RDATA[31:16]}; end
							1'b0: begin rdin <= {16'd0, axi4if.RDATA[15:0]}; end
						endcase
					end
				endcase

				cpustate <= CPUWBACK;
			end else begin
				// No data yet
				cpustate <= CPULOADWAIT;
			end
		end

		CPUSTOREWAIT: begin
			if (axi4if.AWREADY) begin
				axi4if.AWVALID <= 1'b0;
			end

			if (axi4if.WREADY) begin
				// We can now turn off valid and go to next stage
				axi4if.WVALID <= 1'b0;
				axi4if.WSTRB <= 4'h0;
			end

			if (axi4if.BVALID) begin
				axi4if.BREADY <= 1'b0;
				cpustate <= CPUWBACK;
			end else begin
				// Didn't store yet
				cpustate <= CPUSTOREWAIT;
			end
		end
		
		CPUIMATHWAIT: begin
			if (imathbusy) begin
				cpustate <= CPUIMATHWAIT;
			end else begin
				case (aluop)
					`ALU_MUL: begin
						mout <= product;
					end
					`ALU_DIV: begin
						mout <= func3==`F3_DIV ? quotient : quotientu;
					end
					`ALU_REM: begin
						mout <= func3==`F3_REM ? remainder : remainderu;
					end
					default: begin
						mout <= 32'd0;
					end
				endcase
				mwrite <= 1'b1;
				cpustate <= CPUWBACK;
			end
		end

		CPUFMSTALL: begin
			fmaddstrobe <= 1'b0;
			fmsubstrobe <= 1'b0;
			fnmsubstrobe <= 1'b0;
			fnmaddstrobe <= 1'b0;

			if (FPUResultValid) begin
				frwe <= 1'b1;
				frdin <= FPUResult;
				cpustate <= CPUWBACK;
			end else begin
				cpustate <= CPUFMSTALL; // Stall further for fused float
			end
		end
		
		CPUFPUOP: begin
			case (func7)
				`F7_FSGNJ: begin
					frwe <= 1'b1;
					case(func3)
						3'b000: begin // FSGNJ
							frdin <= {frval2[31], frval1[30:0]}; 
						end
						3'b001: begin  // FSGNJN
							frdin <= {~frval2[31], frval1[30:0]};
						end
						3'b010: begin  // FSGNJX
							frdin <= {frval1[31]^frval2[31], frval1[30:0]};
						end
					endcase
					cpustate <= CPUWBACK;
				end
				`F7_FMVXW: begin
					rwren <= 1'b1;
					if (func3 == 3'b000) // FMVXW
						rdin <= frval1;
					else // FCLASS
						rdin <= 32'd0; // TODO: classify the float
					cpustate <= CPUWBACK;
				end
				`F7_FMVWX: begin
					frwe <= 1'b1;
					frdin <= rval1;
					cpustate <= CPUWBACK;
				end
				`F7_FADD: begin
					faddstrobe <= 1'b1;
					cpustate <= CPUFSTALL;
				end
				`F7_FSUB: begin
					fsubstrobe <= 1'b1;
					cpustate <= CPUFSTALL;
				end	
				`F7_FMUL: begin
					fmulstrobe <= 1'b1;
					cpustate <= CPUFSTALL;
				end	
				`F7_FDIV: begin
					fdivstrobe <= 1'b1;
					cpustate <= CPUFSTALL;
				end
				`F7_FCVTSW: begin	
					fi2fstrobe <= (rs2==5'b00000) ? 1'b1:1'b0; // Signed
					fui2fstrobe <= (rs2==5'b00001) ? 1'b1:1'b0; // Unsigned
					cpustate <= CPUFSTALL;
				end
				`F7_FCVTWS: begin
					ff2istrobe <= (rs2==5'b00000) ? 1'b1:1'b0; // Signed
					ff2uistrobe <= (rs2==5'b00001) ? 1'b1:1'b0; // Unsigned
					cpustate <= CPUFSTALL;
				end
				`F7_FSQRT: begin
					fsqrtstrobe <= 1'b1;
					cpustate <= CPUFSTALL;
				end
				`F7_FEQ: begin
					feqstrobe <= (func3==3'b010) ? 1'b1:1'b0; // FEQ
					fltstrobe <= (func3==3'b001) ? 1'b1:1'b0; // FLT
					flestrobe <= (func3==3'b000) ? 1'b1:1'b0; // FLE
					cpustate <= CPUFSTALL;
				end
				`F7_FMAX: begin
					fltstrobe <= 1'b1; // FLT
					cpustate <= CPUFSTALL;
				end
				default: begin
					cpustate <= CPUWBACK;
				end
			endcase
		end

		CPUFSTALL: begin
			faddstrobe <= 1'b0;
			fsubstrobe <= 1'b0;
			fmulstrobe <= 1'b0;
			fdivstrobe <= 1'b0;
			fi2fstrobe <= 1'b0;
			fui2fstrobe <= 1'b0;
			ff2istrobe <= 1'b0;
			ff2uistrobe <= 1'b0;
			fsqrtstrobe <= 1'b0;
			feqstrobe <= 1'b0;
			fltstrobe <= 1'b0;
			flestrobe <= 1'b0;

			if (FPUResultValid) begin
				case (func7)
					`F7_FADD, `F7_FSUB, `F7_FMUL, `F7_FDIV, `F7_FSQRT,`F7_FCVTSW: begin
						frwe <= 1'b1;
						frdin <= FPUResult;
					end
					`F7_FCVTWS: begin
						rwren <= 1'b1;
						rdin <= FPUResult;
					end
					`F7_FEQ: begin
						rwren <= 1'b1;
						rdin <= {31'd0, FPUResult[0]};
					end
					`F7_FMIN: begin
						frwe <= 1'b1;
						if (func3==3'b000) // FMIN
							frdin <= FPUResult[0] ? frval1 : frval2;
						else // FMAX
							frdin <= FPUResult[0] ? frval2 : frval1;
					end
				endcase
				cpustate <= CPUWBACK;
			end else begin
				cpustate <= CPUFSTALL; // Stall further for float op
			end
		end

		CPUWBACK: begin
			case (1'b1)
				instrOneHot[`O_H_LUI]:		rdin <= immed;
				instrOneHot[`O_H_JAL],
				instrOneHot[`O_H_JALR],
				instrOneHot[`O_H_BRANCH]:	rdin <= adjacentPC;
				instrOneHot[`O_H_OP],
				instrOneHot[`O_H_OP_IMM],
				instrOneHot[`O_H_AUIPC]:	rdin <= mwrite ? mout : aluout;
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
			endcase

			rwren <= isrecordingform;
			csrindex_l <= csrindex;

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

			if (wfi)
				cpustate <= CPUWFI;
			else
				cpustate <= CPURETIRE;
		end
	endcase
end

endmodule
