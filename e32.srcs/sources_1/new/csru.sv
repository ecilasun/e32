`timescale 1ns / 1ps

`include "shared.vh"

module csrunit(
	input wire enable,
	input wire [31:0] instruction,				// Raw input instruction
	output bit [4:0] csrindex = `CSR_UNUSED		// Index of selected CSR register
);

// Map CSR register to CSR register file index
// TODO: Could use a memory device with 4096x32bit entries but that's wasteful
always_comb begin
	case ({instruction[31:25], instruction[24:20]})
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

endmodule
