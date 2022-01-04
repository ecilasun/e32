`timescale 1ns / 1ps

module colorpalette(
	input wire gpuclock,
	input wire we,
	input wire [7:0] waddress,
	input wire [7:0] raddress,
	input wire [23:0] din,
	output wire [23:0] dout );

logic [23:0] paletteentries[0:255];

// Set up with VGA color palette on startup
initial begin
	$readmemh("colorpalette.mem", paletteentries);
end

always @(posedge gpuclock) begin // Tied to GPU clock
	if (we)
		paletteentries[waddress] <= din;
end

assign dout = paletteentries[raddress];

endmodule
