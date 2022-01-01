`timescale 1ns / 1ps

module axi4chain(
	axi4 axi4if,
	// IRQ
	output wire [3:0] irq,
	output wire calib_done,
	// UART
	input uartbaseclock,
	output wire uart_rxd_out,
	input wire uart_txd_in,
	// SPI
	input spibaseclock,
	output wire spi_cs_n,
	output wire spi_mosi,
	input wire spi_miso,
	output wire spi_sck );

// S-RAM (scratchpad) @00000000-0001FFFF
wire validwaddr_sram = 4'h0 == axi4if.AWADDR[31:28];
wire validraddr_sram = 4'h0 == axi4if.ARADDR[31:28];
axi4 sramif(axi4if.ACLK, axi4if.ARESETn);
axi4sram SRAM(
	.axi4if(sramif.SLAVE));

// B-RAM (boot program memory ram) @10000000-1000FFFF
wire validwaddr_bram = 4'h1 == axi4if.AWADDR[31:28];
wire validraddr_bram = 4'h1 == axi4if.ARADDR[31:28];
axi4 bramif(axi4if.ACLK, axi4if.ARESETn);
axi4bram BRAM(
	.axi4if(bramif.SLAVE));

// UART @80000000-80000008
wire validwaddr_uart = 4'h8 == axi4if.AWADDR[31:28];
wire validraddr_uart = 4'h8 == axi4if.ARADDR[31:28];
axi4 uartif(axi4if.ACLK, axi4if.ARESETn);
wire uartrcvempty;
axi4uart UART(
	.axi4if(uartif.SLAVE),
	.uartrcvempty(uartrcvempty),
	.uartbaseclock(uartbaseclock),
	.uart_rxd_out(uart_rxd_out),
	.uart_txd_in(uart_txd_in) );

// SPIMaster @90000000-90000000
wire validwaddr_spi = 4'h9 == axi4if.AWADDR[31:28];
wire validraddr_spi = 4'h9 == axi4if.ARADDR[31:28];
axi4 spiif(axi4if.ACLK, axi4if.ARESETn);
axi4spi SPIMaster(
	.axi4if(spiif.SLAVE),
	.spibaseclock(spibaseclock),
	.spi_cs_n(spi_cs_n),
	.spi_mosi(spi_mosi),
	.spi_miso(spi_miso),
	.spi_sck(spi_sck) );

// NULL device active when no valid addres range is selected
wire validwaddr_none = ~(validwaddr_sram | validwaddr_uart | validwaddr_spi | validwaddr_bram);
wire validraddr_none = ~(validraddr_sram | validraddr_uart | validraddr_spi | validraddr_bram);

// Device interrupt requests
assign irq = {3'b000, ~uartrcvempty};

// Dummy device that will noop writes, and return FFFFFFFF on reads.
axi4 dummyif(axi4if.ACLK, axi4if.ARESETn);
axi4dummy NULLDEVICE(
	.axi4if(dummyif.SLAVE) );

// Mirror write channels
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
	end else begin
		axi4if.AWREADY = dummyif.AWREADY;
		axi4if.BRESP = dummyif.BRESP;
		axi4if.BVALID = dummyif.BVALID;
		axi4if.WREADY = dummyif.WREADY;
	end
end

// Mirror read channels
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
	end else begin
		axi4if.ARREADY = dummyif.ARREADY;
		axi4if.RDATA = dummyif.RDATA;
		axi4if.RRESP = dummyif.RRESP;
		axi4if.RVALID = dummyif.RVALID;
	end
end

endmodule
