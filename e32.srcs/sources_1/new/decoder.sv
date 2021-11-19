`timescale 1ns / 1ps

`include "shared.vh"

module decoder(
	input wire enable,
	input wire [31:0] instruction,				// Raw input instruction
	output bit [18:0] instrOneHotOut=18'd0,		// Current instruction class
	output bit isrecordingform = 1'b0,			// High when we can save result to register
	output bit decie = 1'b0,					// Illegal instruction
	output bit [3:0] aluop = 4'h0,				// Current ALU op
	output bit [2:0] bluop = 3'h0,				// Current BLU op
	output bit [2:0] func3 = 3'd0,				// Sub-instruction
	output bit [6:0] func7 = 7'd0,				// Sub-instruction
	output bit [11:0] func12 = 12'd0,			// Sub-instruction
	output bit [4:0] rs1 = 5'd0,				// Source register one
	output bit [4:0] rs2 = 5'd0,				// Source register two
	output bit [4:0] rs3 = 5'd0,				// Used by fused multiplyadd/sub
	output bit [4:0] rd = 5'd0,					// Destination register
	output bit [4:0] csrindex = `CSR_UNUSED,	// Index of selected CSR register
	output bit [31:0] immed = 32'd0,			// Unpacked immediate integer value
	output bit selectimmedasrval2 = 1'b0		// Select rval2 or unpacked integer during EXEC
);

wire [18:0] instrOneHot = {
	instruction[6:2]==`OPCODE_CUSTOM ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_OP ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_OP_IMM ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_LUI ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_STORE ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_LOAD ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_JAL ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_JALR ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_BRANCH ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_AUIPC ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_FENCE ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_SYSTEM ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_FLOAT_OP ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_FLOAT_LDW ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_FLOAT_STW ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_FLOAT_MADD ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_FLOAT_MSUB ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_FLOAT_NMSUB ? 1'b1:1'b0,
	instruction[6:2]==`OPCODE_FLOAT_NMADD ? 1'b1:1'b0 };

// Immed vs rval2 selector
wire selector = instrOneHot[`O_H_OP_IMM] | instrOneHot[`O_H_LOAD] | instrOneHot[`O_H_FLOAT_LDW] | instrOneHot[`O_H_FLOAT_STW] | instrOneHot[`O_H_STORE];
// Any time we didn't have a one-hot bit set, the instruction is invalid
wire illegalinstr = ~(|instrOneHot);
// Every instruction except SYS:3'b000, BRANCH and STORE are recoding form
// i.e. NOT (branch or store) OR (SYS AND at least one bit set)
wire recording = ~(instrOneHot[`O_H_BRANCH] | instrOneHot[`O_H_STORE]) | (instrOneHot[`O_H_SYSTEM] & (|func3));

// Source/destination register indices
wire [4:0] src1 = instruction[19:15];
wire [4:0] src2 = instruction[24:20];
wire [4:0] src3 = instruction[31:27];
wire [4:0] dest = instruction[11:7];

// Sub-functions
wire [2:0] f3 = instruction[14:12];
wire [6:0] f7 = instruction[31:25];
wire [11:0] f12 = instruction[31:20];

// Map CSR register to CSR register file index
// TODO: Could use a memory device with 4096x32bit entries but that's wasteful
always_comb begin
	case ({f7, src2})
		12'h001: csrindex = `CSR_FFLAGS;
		12'h002: csrindex = `CSR_FRM;
		12'h003: csrindex = `CSR_FCSR;
		12'h300: csrindex = `CSR_MSTATUS;
		12'h301: csrindex = `CSR_MISA;
		12'h304: csrindex = `CSR_MIE;
		12'h305: csrindex = `CSR_MTVEC;
		12'h340: csrindex = `CSR_MSCRATCH;
		12'h341: csrindex = `CSR_MEPC;
		12'h342: csrindex = `CSR_MCAUSE;
		12'h343: csrindex = `CSR_MTVAL;
		12'h344: csrindex = `CSR_MIP;
		12'h780: csrindex = `CSR_DCSR;
		12'h781: csrindex = `CSR_DPC;
		12'h800: csrindex = `CSR_TIMECMPLO;
		12'h801: csrindex = `CSR_TIMECMPHI;
		12'hB00: csrindex = `CSR_CYCLELO;
		12'hB80: csrindex = `CSR_CYCLEHI;
		12'hC01: csrindex = `CSR_TIMELO;
		12'hC02: csrindex = `CSR_RETILO;
		12'hC81: csrindex = `CSR_TIMEHI;
		12'hC82: csrindex = `CSR_RETIHI;
		12'hF14: csrindex = `CSR_HARTID;
		default: csrindex = `CSR_UNUSED;
	endcase
end

// Shift in decoded values
always_comb begin
	if (enable) begin
		rs1 = src1;
		rs2 = src2;
		rs3 = src3;
		rd = dest;
		func3 = f3;
		func7 = f7;
		func12 = f12;
		instrOneHotOut = instrOneHot;
		selectimmedasrval2 = selector;	// Use rval2 or immed
		decie = illegalinstr;			// If no bit is set, this is an illegal instruction
		isrecordingform = recording;	// Everything except branches and store records result into rd
	end
end

// Work out ALU op
always_comb begin
	if (enable) begin
		case (1'b1)
			instrOneHot[`O_H_OP]: begin
				if (instruction[25]==1'b0) begin
					// Base integer ALU instructions
					unique case (instruction[14:12])
						3'b000: aluop = instruction[30] == 1'b0 ? `ALU_ADD : `ALU_SUB;
						3'b001: aluop = `ALU_SLL;
						3'b011: aluop = `ALU_SLTU;
						3'b010: aluop = `ALU_SLT;
						3'b110: aluop = `ALU_OR;
						3'b111: aluop = `ALU_AND;
						3'b101: aluop = instruction[30] == 1'b0 ? `ALU_SRL : `ALU_SRA;
						3'b100: aluop = `ALU_XOR;
					endcase
				end else begin
					// M-extension instructions
					unique case (instruction[14:12])
						3'b000, 3'b001, 3'b010, 3'b011: aluop = `ALU_MUL;
						3'b100, 3'b101: aluop = `ALU_DIV;
						3'b110, 3'b111: aluop = `ALU_REM;
					endcase
				end
			end

			instrOneHot[`O_H_OP_IMM]: begin
				unique case (instruction[14:12])
					3'b000: aluop = `ALU_ADD; // NOTE: No immediate mode sub exists
					3'b001: aluop = `ALU_SLL;
					3'b011: aluop = `ALU_SLTU;
					3'b010: aluop = `ALU_SLT;
					3'b110: aluop = `ALU_OR;
					3'b111: aluop = `ALU_AND;
					3'b101: aluop = instruction[30] == 1'b0 ? `ALU_SRL : `ALU_SRA;
					3'b100: aluop = `ALU_XOR;
				endcase
			end
	
			default: begin
				aluop = `ALU_NONE;
			end
		endcase
	end
end

// Work out BLU op
always_comb begin
	if (enable) begin
		case (1'b1)
			instrOneHot[`O_H_BRANCH]: begin
				unique case (instruction[14:12])
					3'b000: bluop = `ALU_EQ;
					3'b001: bluop = `ALU_NE;
					3'b011: bluop = `ALU_NONE;
					3'b010: bluop = `ALU_NONE;
					3'b110: bluop = `ALU_LU;
					3'b111: bluop = `ALU_GEU;
					3'b101: bluop = `ALU_GE;
					3'b100: bluop = `ALU_L;
				endcase
			end
	
			default: begin
				bluop = `ALU_NONE;
			end
		endcase
	end
end

// Work out immediate value
always_comb begin
	if (enable) begin
		case (1'b1)
			instrOneHot[`O_H_LUI], instrOneHot[`O_H_AUIPC]: begin	
				immed = {instruction[31:12], 12'd0};
			end
	
			instrOneHot[`O_H_FLOAT_STW], instrOneHot[`O_H_STORE]: begin
				immed = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
			end
	
			instrOneHot[`O_H_OP_IMM], instrOneHot[`O_H_FLOAT_LDW], instrOneHot[`O_H_LOAD], instrOneHot[`O_H_JALR]: begin
				immed = {{21{instruction[31]}}, instruction[30:20]};
			end
	
			instrOneHot[`O_H_JAL]: begin
				immed = {{12{instruction[31]}}, instruction[19:12], instruction[20], instruction[30:21], 1'b0};
			end
		
			instrOneHot[`O_H_BRANCH]: begin
				immed = {{20{instruction[31]}}, instruction[7], instruction[30:25], instruction[11:8], 1'b0};
			end
	
			instrOneHot[`O_H_SYSTEM]: begin
				immed = {27'd0, instruction[19:15]};
			end
	
			default: begin
				immed = 32'd0;
			end
		endcase
	end
end

endmodule
