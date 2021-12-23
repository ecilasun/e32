`timescale 1ns / 1ps

`include "shared.vh"

module branchlogicunit(
	output bit branchout = 1'b0,
	input wire [31:0] val1,
	input wire [31:0] val2,
	input wire [2:0] bluop);

wire [5:0] aluonehot = {
	bluop == `ALU_EQ ? 1'b1 : 1'b0,
	bluop == `ALU_NE ? 1'b1 : 1'b0,
	bluop == `ALU_L ? 1'b1 : 1'b0,
	bluop == `ALU_GE ? 1'b1 : 1'b0,
	bluop == `ALU_LU ? 1'b1 : 1'b0,
	bluop == `ALU_GEU ? 1'b1 : 1'b0 };

wire eq = val1 == val2 ? 1'b1:1'b0;
wire sless = $signed(val1) < $signed(val2) ? 1'b1:1'b0;
wire less = val1 < val2 ? 1'b1:1'b0;

// Branch ALU
always_comb begin
	case (1'b1)
		// BRANCH ALU
		aluonehot[5]:	branchout = eq;
		aluonehot[4]:	branchout = ~eq;
		aluonehot[3]:	branchout = sless;
		aluonehot[2]:	branchout = ~sless;
		aluonehot[1]:	branchout = less;
		/*aluonehot[0]*/
		default:		branchout = ~less;
	endcase
end

endmodule
