// ------------------------------------------
// Integer uncompressed instructions (2'b11)
// ------------------------------------------

`define OPCODE_CUSTOM       7'b0001011 // - Custom instruction
`define OPCODE_OP		    7'b0110011
`define OPCODE_OP_IMM 	    7'b0010011
`define OPCODE_LUI		    7'b0110111
`define OPCODE_STORE	    7'b0100011
`define OPCODE_LOAD		    7'b0000011
`define OPCODE_JAL		    7'b1101111
`define OPCODE_JALR		    7'b1100111
`define OPCODE_BRANCH	    7'b1100011
`define OPCODE_AUIPC	    7'b0010111
`define OPCODE_FENCE	    7'b0001111
`define OPCODE_SYSTEM	    7'b1110011
`define OPCODE_FLOAT_OP     7'b1010011
`define OPCODE_FLOAT_LDW    7'b0000111
`define OPCODE_FLOAT_STW    7'b0100111
`define OPCODE_FLOAT_MADD   7'b1000011
`define OPCODE_FLOAT_MSUB   7'b1000111
`define OPCODE_FLOAT_NMSUB  7'b1001011
`define OPCODE_FLOAT_NMADD  7'b1001111

// ------------------------------------------
// Instruction decoder one-hot states
// ------------------------------------------

`define O_H_CUSTOM			18
`define O_H_OP				17
`define O_H_OP_IMM			16
`define O_H_LUI				15
`define O_H_STORE			14
`define O_H_LOAD			13
`define O_H_JAL				12
`define O_H_JALR			11
`define O_H_BRANCH			10
`define O_H_AUIPC			9
`define O_H_FENCE			8
`define O_H_SYSTEM			7
`define O_H_FLOAT_OP		6
`define O_H_FLOAT_LDW		5
`define O_H_FLOAT_STW		4
`define O_H_FLOAT_MADD		3
`define O_H_FLOAT_MSUB		2
`define O_H_FLOAT_NMSUB		1
`define O_H_FLOAT_NMADD		0

// ------------------------------------------
// ALU ops
// ------------------------------------------

`define ALU_NONE		4'd0
// Integer base
`define ALU_ADD 		4'd1
`define ALU_SUB			4'd2
`define ALU_SLL			4'd3
`define ALU_SLT			4'd4
`define ALU_SLTU		4'd5
`define ALU_XOR			4'd6
`define ALU_SRL			4'd7
`define ALU_SRA			4'd8
`define ALU_OR			4'd9
`define ALU_AND			4'd10
// Mul/Div
`define ALU_MUL			4'd11
`define ALU_DIV			4'd12
`define ALU_REM			4'd13
// Branch
`define ALU_EQ			3'd1
`define ALU_NE			3'd2
`define ALU_L			3'd3
`define ALU_GE			3'd4
`define ALU_LU			3'd5
`define ALU_GEU			3'd6

// ------------------------------------------
// CSR related
// ------------------------------------------

`define CSR_REGISTER_COUNT 24

`define CSR_UNUSED		5'd0
`define CSR_FFLAGS		5'd1
`define CSR_FRM			5'd2
`define CSR_FCSR		5'd3
`define CSR_MSTATUS		5'd4
`define CSR_MISA		5'd5
`define CSR_MIE			5'd6
`define CSR_MTVEC		5'd7
`define CSR_MSCRATCH	5'd8
`define CSR_MEPC		5'd9
`define CSR_MCAUSE		5'd10
`define CSR_MTVAL		5'd11
`define CSR_MIP			5'd12
`define CSR_DCSR		5'd13
`define CSR_DPC			5'd14
`define CSR_TIMECMPLO	5'd15
`define CSR_TIMECMPHI	5'd16
`define CSR_CYCLELO		5'd17
`define CSR_CYCLEHI		5'd18
`define CSR_TIMELO		5'd19
`define CSR_RETILO		5'd20
`define CSR_TIMEHI		5'd21
`define CSR_RETIHI		5'd22
`define CSR_HARTID		5'd23
