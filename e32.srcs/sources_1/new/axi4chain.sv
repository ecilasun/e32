`timescale 1ns / 1ps

module axi4chain(
	axi4.SLAVE axi4if,
	FPGADeviceClocks.DEFAULT clocks,
	FPGADeviceWires.DEFAULT wires,
	GPUDataOutput.DEFAULT gpudata,
	output wire [3:0] irq,
	output wire calib_done,
	output wire ui_clk );

// ------------------------------------------------------------------------------------
// Main system memory
// ------------------------------------------------------------------------------------

// DDR3 (256Mbytes, main system memory) @00000000-0FFFFFFF
wire validwaddr_ddr3 = 4'h0 == axi4if.AWADDR[31:28];
wire validraddr_ddr3 = 4'h0 == axi4if.ARADDR[31:28];
axi4 ddr3if(axi4if.ACLK, axi4if.ARESETn);
axi4ddr3 DDR3(
	.axi4if(ddr3if),
	.clocks(clocks),
	.wires(wires),
	.calib_done(calib_done),
	.ui_clk(ui_clk) );

// ------------------------------------------------------------------------------------
// Internal block memory
// ------------------------------------------------------------------------------------

wire validw_internalmem = (4'h1 == axi4if.AWADDR[31:28]);
wire validr_internalmem = (4'h1 == axi4if.ARADDR[31:28]);

// B-RAM (64KBytes, boot program memory ram) @10000000-1000FFFF
wire validwaddr_bram = validw_internalmem & (axi4if.AWADDR[19:16] == 4'h0);
wire validraddr_bram = validr_internalmem & (axi4if.ARADDR[19:16] == 4'h0);
axi4 bramif(axi4if.ACLK, axi4if.ARESETn);
axi4bram BRAM(
	.axi4if(bramif));

// S-RAM (128KBytes, scratchpad memory) @10010000-1002FFFF
wire validwaddr_sram = validw_internalmem & (axi4if.AWADDR[19:16] != 4'h0);
wire validraddr_sram = validr_internalmem & (axi4if.ARADDR[19:16] != 4'h0);
axi4 sramif(axi4if.ACLK, axi4if.ARESETn);
axi4sram SRAM(
	.axi4if(sramif));

// ------------------------------------------------------------------------------------
// Memory mapped hardware
// ------------------------------------------------------------------------------------

wire validw_devicemap = (4'h2 == axi4if.AWADDR[31:28]);
wire validr_devicemap = (4'h2 == axi4if.ARADDR[31:28]);

// UART (4x3 bytes, serial comm data and status i/o ports) @20000000-20000008
wire validwaddr_uart = validw_devicemap & (4'h0 == axi4if.AWADDR[15:12]);
wire validraddr_uart = validr_devicemap & (4'h0 == axi4if.ARADDR[15:12]);
axi4 uartif(axi4if.ACLK, axi4if.ARESETn);
wire uartrcvempty;
axi4uart UART(
	.axi4if(uartif),
	.clocks(clocks),
	.wires(wires),
	.uartrcvempty(uartrcvempty) );

// SPIMaster (4 bytes, SPI i/o port) @20001000-20001000
wire validwaddr_spi = validw_devicemap & (4'h1 == axi4if.AWADDR[15:12]);
wire validraddr_spi = validr_devicemap & (4'h1 == axi4if.ARADDR[15:12]);
axi4 spiif(axi4if.ACLK, axi4if.ARESETn);
axi4spi SPIMaster(
	.axi4if(spiif),
	.clocks(clocks),
	.wires(wires) );

// ------------------------------------------------------------------------------------
// GPU
// ------------------------------------------------------------------------------------

// GPU @40000000-...
// FB0: 80000000
// FB1: 80020000
// PAL: 80040000
wire validwaddr_gpu = 4'h4 == axi4if.AWADDR[31:28];
wire validraddr_gpu = 4'h4 == axi4if.ARADDR[31:28];
axi4 gpuif(axi4if.ACLK, axi4if.ARESETn);
axi4gpu GPU(
	.axi4if(gpuif),
	.clocks(clocks),
	.wires(wires),
	.gpudata(gpudata));

// NULL device active when no valid addres range is selected
wire validwaddr_none = ~(validwaddr_sram | validwaddr_uart | validwaddr_spi | validwaddr_bram | validwaddr_ddr3 | validwaddr_gpu);
wire validraddr_none = ~(validraddr_sram | validraddr_uart | validraddr_spi | validraddr_bram | validraddr_ddr3 | validraddr_gpu);

// ------------------------------------------------------------------------------------
// Interrupt setup
// ------------------------------------------------------------------------------------

assign irq = {3'b000, ~uartrcvempty};

// ------------------------------------------------------------------------------------
// Fallback dummy device
// ------------------------------------------------------------------------------------

axi4 dummyif(axi4if.ACLK, axi4if.ARESETn);
axi4dummy NULLDEVICE(
	.axi4if(dummyif.SLAVE) );

// ------------------------------------------------------------------------------------
// Write router
// ------------------------------------------------------------------------------------

wire [31:0] waddr = {4'h0,axi4if.AWADDR[27:0]};

always_comb begin
	uartif.AWADDR = validwaddr_uart ? waddr : 32'dz;
	uartif.AWVALID = validwaddr_uart ? axi4if.AWVALID : 1'b0;
	uartif.WDATA = validwaddr_uart ? axi4if.WDATA : 32'dz;
	uartif.WSTRB = validwaddr_uart ? axi4if.WSTRB : 4'h0;
	uartif.WVALID = validwaddr_uart ? axi4if.WVALID : 1'b0;
	uartif.BREADY = validwaddr_uart ? axi4if.BREADY : 1'b0;

	sramif.AWADDR = validwaddr_sram ? waddr : 32'dz;
	sramif.AWVALID = validwaddr_sram ? axi4if.AWVALID : 1'b0;
	sramif.WDATA = validwaddr_sram ? axi4if.WDATA : 32'dz;
	sramif.WSTRB = validwaddr_sram ? axi4if.WSTRB : 4'h0;
	sramif.WVALID = validwaddr_sram ? axi4if.WVALID : 1'b0;
	sramif.BREADY = validwaddr_sram ? axi4if.BREADY : 1'b0;

	spiif.AWADDR = validwaddr_spi ? waddr : 32'dz;
	spiif.AWVALID = validwaddr_spi ? axi4if.AWVALID : 1'b0;
	spiif.WDATA = validwaddr_spi ? axi4if.WDATA : 32'dz;
	spiif.WSTRB = validwaddr_spi ? axi4if.WSTRB : 4'h0;
	spiif.WVALID = validwaddr_spi ? axi4if.WVALID : 1'b0;
	spiif.BREADY = validwaddr_spi ? axi4if.BREADY : 1'b0;

	bramif.AWADDR = validwaddr_bram ? waddr : 32'dz;
	bramif.AWVALID = validwaddr_bram ? axi4if.AWVALID : 1'b0;
	bramif.WDATA = validwaddr_bram ? axi4if.WDATA : 32'dz;
	bramif.WSTRB = validwaddr_bram ? axi4if.WSTRB : 4'h0;
	bramif.WVALID = validwaddr_bram ? axi4if.WVALID : 1'b0;
	bramif.BREADY = validwaddr_bram ? axi4if.BREADY : 1'b0;

	ddr3if.AWADDR = validwaddr_ddr3 ? waddr : 32'dz;
	ddr3if.AWVALID = validwaddr_ddr3 ? axi4if.AWVALID : 1'b0;
	ddr3if.WDATA = validwaddr_ddr3 ? axi4if.WDATA : 32'dz;
	ddr3if.WSTRB = validwaddr_ddr3 ? axi4if.WSTRB : 4'h0;
	ddr3if.WVALID = validwaddr_ddr3 ? axi4if.WVALID : 1'b0;
	ddr3if.BREADY = validwaddr_ddr3 ? axi4if.BREADY : 1'b0;

	gpuif.AWADDR = validwaddr_gpu ? waddr : 32'dz;
	gpuif.AWVALID = validwaddr_gpu ? axi4if.AWVALID : 1'b0;
	gpuif.WDATA = validwaddr_gpu ? axi4if.WDATA : 32'dz;
	gpuif.WSTRB = validwaddr_gpu ? axi4if.WSTRB : 4'h0;
	gpuif.WVALID = validwaddr_gpu ? axi4if.WVALID : 1'b0;
	gpuif.BREADY = validwaddr_gpu ? axi4if.BREADY : 1'b0;

	dummyif.AWADDR = validwaddr_none ? waddr : 32'dz;
	dummyif.AWVALID = validwaddr_none ? axi4if.AWVALID : 1'b0;
	dummyif.WDATA = validwaddr_none ? axi4if.WDATA : 32'dz;
	dummyif.WSTRB = validwaddr_none ? axi4if.WSTRB : 4'h0;
	dummyif.WVALID = validwaddr_none ? axi4if.WVALID : 1'b0;
	dummyif.BREADY = validwaddr_none ? axi4if.BREADY : 1'b0;

	if (validwaddr_uart) begin
		axi4if.AWREADY = uartif.AWREADY;
		axi4if.BRESP = uartif.BRESP;
		axi4if.BVALID = uartif.BVALID;
		axi4if.WREADY = uartif.WREADY;
	end else if (validwaddr_sram) begin
		axi4if.AWREADY = sramif.AWREADY;
		axi4if.BRESP = sramif.BRESP;
		axi4if.BVALID = sramif.BVALID;
		axi4if.WREADY = sramif.WREADY;
	end else if (validwaddr_spi) begin
		axi4if.AWREADY = spiif.AWREADY;
		axi4if.BRESP = spiif.BRESP;
		axi4if.BVALID = spiif.BVALID;
		axi4if.WREADY = spiif.WREADY;
	end else if (validwaddr_bram) begin
		axi4if.AWREADY = bramif.AWREADY;
		axi4if.BRESP = bramif.BRESP;
		axi4if.BVALID = bramif.BVALID;
		axi4if.WREADY = bramif.WREADY;
	end else if (validwaddr_ddr3) begin
		axi4if.AWREADY = ddr3if.AWREADY;
		axi4if.BRESP = ddr3if.BRESP;
		axi4if.BVALID = ddr3if.BVALID;
		axi4if.WREADY = ddr3if.WREADY;
	end else if (validwaddr_gpu) begin
		axi4if.AWREADY = gpuif.AWREADY;
		axi4if.BRESP = gpuif.BRESP;
		axi4if.BVALID = gpuif.BVALID;
		axi4if.WREADY = gpuif.WREADY;
	end else begin
		axi4if.AWREADY = dummyif.AWREADY;
		axi4if.BRESP = dummyif.BRESP;
		axi4if.BVALID = dummyif.BVALID;
		axi4if.WREADY = dummyif.WREADY;
	end
end

// ------------------------------------------------------------------------------------
// Read router
// ------------------------------------------------------------------------------------

wire [31:0] raddr = {4'h0,axi4if.ARADDR[27:0]};

always_comb begin

	uartif.ARADDR = validraddr_uart ? raddr : 32'dz;
	uartif.ARVALID = validraddr_uart ? axi4if.ARVALID : 1'b0;
	uartif.RREADY = validraddr_uart ? axi4if.RREADY : 1'b0;

	sramif.ARADDR = validraddr_sram ? raddr : 32'dz;
	sramif.ARVALID = validraddr_sram ? axi4if.ARVALID : 1'b0;
	sramif.RREADY = validraddr_sram ? axi4if.RREADY : 1'b0;

	spiif.ARADDR = validraddr_spi ? raddr : 32'dz;
	spiif.ARVALID = validraddr_spi ? axi4if.ARVALID : 1'b0;
	spiif.RREADY = validraddr_spi ? axi4if.RREADY : 1'b0;

	bramif.ARADDR = validraddr_bram ? raddr : 32'dz;
	bramif.ARVALID = validraddr_bram ? axi4if.ARVALID : 1'b0;
	bramif.RREADY = validraddr_bram ? axi4if.RREADY : 1'b0;

	ddr3if.ARADDR = validraddr_ddr3 ? raddr : 32'dz;
	ddr3if.ARVALID = validraddr_ddr3 ? axi4if.ARVALID : 1'b0;
	ddr3if.RREADY = validraddr_ddr3 ? axi4if.RREADY : 1'b0;

	gpuif.ARADDR = validraddr_gpu ? raddr : 32'dz;
	gpuif.ARVALID = validraddr_gpu ? axi4if.ARVALID : 1'b0;
	gpuif.RREADY = validraddr_gpu ? axi4if.RREADY : 1'b0;

	dummyif.ARADDR = validraddr_none ? raddr : 32'dz;
	dummyif.ARVALID = validraddr_none ? axi4if.ARVALID : 1'b0;
	dummyif.RREADY = validraddr_none ? axi4if.RREADY : 1'b0;

	if (validraddr_uart) begin
		axi4if.ARREADY = uartif.ARREADY;
		axi4if.RDATA = uartif.RDATA;
		axi4if.RRESP = uartif.RRESP;
		axi4if.RVALID = uartif.RVALID;
	end else if (validraddr_sram) begin
		axi4if.ARREADY = sramif.ARREADY;
		axi4if.RDATA = sramif.RDATA;
		axi4if.RRESP = sramif.RRESP;
		axi4if.RVALID = sramif.RVALID;
	end else if (validraddr_spi) begin
		axi4if.ARREADY = spiif.ARREADY;
		axi4if.RDATA = spiif.RDATA;
		axi4if.RRESP = spiif.RRESP;
		axi4if.RVALID = spiif.RVALID;
	end else if (validraddr_bram) begin
		axi4if.ARREADY = bramif.ARREADY;
		axi4if.RDATA = bramif.RDATA;
		axi4if.RRESP = bramif.RRESP;
		axi4if.RVALID = bramif.RVALID;
	end else if (validraddr_ddr3) begin
		axi4if.ARREADY = ddr3if.ARREADY;
		axi4if.RDATA = ddr3if.RDATA;
		axi4if.RRESP = ddr3if.RRESP;
		axi4if.RVALID = ddr3if.RVALID;
	end else if (validraddr_gpu) begin
		axi4if.ARREADY = gpuif.ARREADY;
		axi4if.RDATA = gpuif.RDATA;
		axi4if.RRESP = gpuif.RRESP;
		axi4if.RVALID = gpuif.RVALID;
	end else begin
		axi4if.ARREADY = dummyif.ARREADY;
		axi4if.RDATA = dummyif.RDATA;
		axi4if.RRESP = dummyif.RRESP;
		axi4if.RVALID = dummyif.RVALID;
	end
end

endmodule
