`timescale 1ns / 1ps

`include "shared.vh"

module cpu(
	input wire cpuclock,
	input wire reset,
	input wire irqtrigger,
	input [3:0] irqlines,
	output logic [31:0] busaddress = 32'd0,	// memory or device address
	inout wire [31:0] busdata,				// data from/to memory
	output logic busre = 1'b0,				// memory read enable
	output logic [3:0] buswe = 4'h0,		// memory write enable (byte mask)
	input wire busbusy						// high when bus busy after r/w request
	);

// -----------------------------------------------------------------------
// Bidirectional bus logic
// -----------------------------------------------------------------------

logic [31:0] dout = {25'd0,`OPCODE_OP_IMM,2'b11}; // NOOP
assign busdata = (|buswe) ? dout : 32'dz;

// ------------------------------------------
// Internals
// ------------------------------------------

// Reset vector is in S-RAM
logic [31:0] PC = 32'h10000000;
logic [31:0] nextPC = 32'h10000000;
logic decena = 1'b0;
logic aluenable = 1'b0;

// ------------------------------------------
// State machine
// ------------------------------------------

logic [4:0] next_state;
logic [4:0] current_state;

localparam S_RESET = 5'd1;
localparam S_FETCH = 5'd2;
localparam S_EXEC  = 5'd4;
localparam S_WBACK = 5'd8;
localparam S_RETIRE = 5'd16;

always @(current_state) begin
	case (current_state)
		S_RESET:	begin next_state = S_RETIRE; end
		S_RETIRE:	begin next_state = S_FETCH; end
		S_FETCH:	begin next_state = S_EXEC; end
		S_EXEC:		begin next_state = S_WBACK; end
		S_WBACK:	begin next_state = S_RETIRE; end
		default:	begin next_state = current_state; end
	endcase
end

always @(posedge cpuclock) begin
	if (reset) begin
		current_state = S_RESET;
	end else begin
		current_state = next_state;
	end
end

// ------------------------------------------
// Decoder unit
// ------------------------------------------

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
wire [3:0] aluop, bluop;

decoder InstructionDecoder(
	.enable(decena),
	.instruction(busdata),
	.instrOneHotOut(instrOneHot),
	.isrecordingform(isrecordingform),
	.decie(illlegalInstruction),
	.aluop(aluop),
	.bluop(bluop),
	.func3(func3),
	.func7(func7),
	.func12(func12),
	.rs1(rs1), // Address calculation for LOAD
	.rs2(rs2),
	.rs3(rs3),
	.rd(rd),
	.csrindex(csrindex),
	.immed(immed),
	.selectimmedasrval2(selectimmedasrval2) );

// ------------------------------------------
// Register file
// ------------------------------------------

logic rwren = 1'b0;
logic [31:0] rdin = 32'd0, wback = 32'd0;
wire [31:0] rval1, rval2;

registerfile IntegerRegisters(
	.clock(cpuclock),
	.rs1(rs1),
	.rs2(rs2),
	.rd(rd),
	.wren(rwren),
	.din(rdin),
	.rval1(rval1),
	.rval2(rval2) );

// ------------------------------------------
// ALU / BLU
// ------------------------------------------

wire [31:0] aluout;

arithmeticlogicunit ALU(
	.enable(aluenable),
	.aluout(aluout),
	.func3(func3),
	.val1(rval1),
	.val2(selectimmedasrval2 ? immed : rval2),
	.aluop(aluop) );

wire branchout;

branchlogicunit BLU(
	.branchout(branchout),
	.val1(rval1),
	.val2(rval2),
	.bluop(bluop) );

// ------------------------------------------
// Execution unit
// ------------------------------------------

always @(posedge cpuclock) begin

	if (reset) begin

		PC <= 32'h10000000;
		nextPC <= 32'h10000000;
		decena <= 1'b0;
		aluenable <= 1'b0;

	end else begin

		rwren <= 1'b0;
		buswe <= 4'h0;
		busre <= 1'b0;
		dout <= 32'd0;
		decena <= 1'b0;
		aluenable <= 1'b0;

		case (current_state)
			S_FETCH: begin
				// TODO: CSR load
				// TODO: interrupt checks
				decena <= 1'b1;
			end

			S_EXEC: begin
				aluenable <= 1'b1;
				if (instrOneHot[`O_H_LOAD] | instrOneHot[`O_H_STORE])
					busaddress <= rval1 + immed;
				busre <= instrOneHot[`O_H_LOAD];
				case (1'b1)
					instrOneHot[`O_H_JAL]:		nextPC <= PC + immed;
					instrOneHot[`O_H_JALR]:		nextPC <= rval1 + immed;
					instrOneHot[`O_H_BRANCH]:	nextPC <= branchout ? PC + immed : PC + 32'd4;
					default:					nextPC <= PC + 32'd4;
				endcase
			end

			S_WBACK: begin
				// Stash the LOAD result to a register
				unique case (1'b1)
					instrOneHot[`O_H_STORE]: begin
						case (func3)
							3'b000: begin // 8bit
								dout <= {rval2[7:0], rval2[7:0], rval2[7:0], rval2[7:0]};
								//buswe <= 4'h1 << busaddress[1:0];
								case (busaddress[1:0])
									2'b11: begin buswe <= 4'h8; end
									2'b10: begin buswe <= 4'h4; end
									2'b01: begin buswe <= 4'h2; end
									2'b00: begin buswe <= 4'h1; end
								endcase
							end
							3'b001: begin // 16bit
								dout <= {rval2[15:0], rval2[15:0]};
								//buswe <= 4'h3 << {busaddress[1],1'b0};
								case (busaddress[1])
									1'b1: begin buswe <= 4'hC; end
									1'b0: begin buswe <= 4'h3; end
								endcase
							end
							3'b010: begin // 32bit
								//dout <= (instrOneHot[`O_H_FLOAT_STW]) ? frval2 : rval2;
								dout <= rval2;
								buswe <= 4'hF;
							end
						endcase
					end
					instrOneHot[`O_H_AUIPC]:						begin wback <= PC + immed; end
					instrOneHot[`O_H_LUI]:							begin wback <= immed; end
					instrOneHot[`O_H_JAL]:							begin wback <= PC + 32'd4; end
					instrOneHot[`O_H_JALR]:							begin wback <= PC + 32'd4; end
					instrOneHot[`O_H_BRANCH]:						begin wback <= PC + 32'd4; end
					instrOneHot[`O_H_OP], instrOneHot[`O_H_OP_IMM]:	begin wback <= aluout; end
				endcase
				// TODO: CSR writeback
			end

			S_RETIRE: begin
				// TODO: Route PC&busaddress to handle interrupts (irqtrigger/irqlines) or exceptions (illegal instruction/ebreak/syscall etc)
				PC <= nextPC;
				busaddress <= nextPC;

				// Read next instruction
				busre <= 1'b1;

				// Register value update if required
				rwren <= isrecordingform;

				if (instrOneHot[`O_H_LOAD]) begin
					case (func3)
						3'b000: begin // BYTE with sign extension
							case (busaddress[1:0])
								2'b11: begin rdin <= {{24{busdata[31]}}, busdata[31:24]}; end
								2'b10: begin rdin <= {{24{busdata[23]}}, busdata[23:16]}; end
								2'b01: begin rdin <= {{24{busdata[15]}}, busdata[15:8]}; end
								2'b00: begin rdin <= {{24{busdata[7]}},  busdata[7:0]}; end
							endcase
						end
						3'b001: begin // WORD with sign extension
							case (busaddress[1])
								1'b1: begin rdin <= {{16{busdata[31]}}, busdata[31:16]}; end
								1'b0: begin rdin <= {{16{busdata[15]}}, busdata[15:0]}; end
							endcase
						end
						3'b010: begin // DWORD
							//if (instrOneHot[`O_H_FLOAT_LDW])
							//	frdin <= busdata[31:0];
							//else
								rdin <= busdata[31:0];
						end
						3'b100: begin // BYTE with zero extension
							case (busaddress[1:0])
								2'b11: begin rdin <= {24'd0, busdata[31:24]}; end
								2'b10: begin rdin <= {24'd0, busdata[23:16]}; end
								2'b01: begin rdin <= {24'd0, busdata[15:8]}; end
								2'b00: begin rdin <= {24'd0, busdata[7:0]}; end
							endcase
						end
						3'b101: begin // WORD with zero extension
							case (busaddress[1])
								1'b1: begin rdin <= {16'd0, busdata[31:16]}; end
								1'b0: begin rdin <= {16'd0, busdata[15:0]}; end
							endcase
						end
					endcase
				end else begin
					rdin <= wback;
				end 
			end

			default: begin
				// 
			end

		endcase

	end
end

endmodule
