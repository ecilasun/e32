`timescale 1ns / 1ps

module axi4uart(
	axi4.SLAVE axi4if,
	FPGADeviceWires.DEFAULT wires,
	FPGADeviceClocks.DEFAULT clocks,
	output wire uartrcvempty );

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

//logic [31:0] writeaddress = 32'd0;
logic [7:0] din = 8'h00;
logic [3:0] we = 4'h0;

// ----------------------------------------------------------------------------
// UART Transmitter
// ----------------------------------------------------------------------------

bit transmitbyte = 1'b0;
bit [7:0] datatotransmit = 8'h00;
wire uarttxbusy;

async_transmitter UART_transmit(
	.clk(clocks.uartbaseclock),
	.TxD_start(transmitbyte),
	.TxD_data(datatotransmit),
	.TxD(wires.uart_rxd_out),
	.TxD_busy(uarttxbusy) );

wire [7:0] uartsenddout;
bit uartsendre = 1'b0;
wire uartsendfull, uartsendempty, uartsendvalid;

uartout UARTDataOutFIFO(
	.full(uartsendfull),
	.din(din),
	.wr_en( (|we) ),
	.wr_clk(axi4if.ACLK),
	.empty(uartsendempty),
	.valid(uartsendvalid),
	.dout(uartsenddout),
	.rd_en(uartsendre),
	.rd_clk(clocks.uartbaseclock),
	.rst(~axi4if.ARESETn) );

bit [1:0] uartwritemode = 2'b00;

always @(posedge clocks.uartbaseclock) begin
	uartsendre <= 1'b0;
	transmitbyte <= 1'b0;
	unique case(uartwritemode)
		2'b00: begin // IDLE
			if (~uartsendempty & (~uarttxbusy)) begin
				uartsendre <= 1'b1;
				uartwritemode <= 2'b01; // WRITE
			end
		end
		2'b01: begin // WRITE
			if (uartsendvalid) begin
				transmitbyte <= 1'b1;
				datatotransmit <= uartsenddout;
				uartwritemode <= 2'b10; // FINALIZE
			end
		end
		default/*2'b10*/: begin // FINALIZE
			// Need to give UARTTX one clock to
			// kick 'busy' for any adjacent
			// requests which didn't set busy yet
			uartwritemode <= 2'b00; // IDLE
		end
	endcase
end

// ----------------------------------------------------------------------------
// UART Receiver
// ----------------------------------------------------------------------------

wire uartbyteavailable;
wire [7:0] uartbytein;

async_receiver UART_receive(
	.clk(clocks.uartbaseclock),
	.RxD(wires.uart_txd_in),
	.RxD_data_ready(uartbyteavailable),
	.RxD_data(uartbytein),
	.RxD_idle(),
	.RxD_endofpacket() );

wire uartrcvfull, uartrcvvalid;
bit [7:0] uartrcvdin = 8'h00;
wire [7:0] uartrcvdout;
bit uartrcvre = 1'b0, uartrcvwe = 1'b0;

uartin UARTDataInFIFO(
	.full(uartrcvfull),
	.din(uartrcvdin),
	.wr_en(uartrcvwe),
	.wr_clk(clocks.uartbaseclock),
	.empty(uartrcvempty),
	.dout(uartrcvdout),
	.rd_en(uartrcvre),
	.valid(uartrcvvalid),
	.rd_clk(axi4if.ACLK),
	.rst(~axi4if.ARESETn) );

always @(posedge clocks.uartbaseclock) begin
	uartrcvwe <= 1'b0;
	// NOTE: Any byte that won't fit into the FIFO will be dropped
	// Make sure to consume them quickly on arrival!
	if (uartbyteavailable & (~uartsendfull)) begin
		uartrcvwe <= 1'b1;
		uartrcvdin <= uartbytein;
	end
end

// Main state machine
always @(posedge axi4if.ACLK) begin
	// Write address
	case (waddrstate)
		2'b00: begin
			if (axi4if.AWVALID & (~uartsendfull)) begin
				//writeaddress <= axi4if.AWADDR; // TODO: select subdevice using some bits of address
				axi4if.AWREADY <= 1'b1;
				waddrstate <= 2'b01;
			end
		end
		default/*2'b01*/: begin
			axi4if.AWREADY <= 1'b0;
			waddrstate <= 2'b00;
		end
	endcase
end

always @(posedge axi4if.ACLK) begin
	// Write data
	we <= 4'h0;
	case (writestate)
		2'b00: begin
			if (axi4if.WVALID & (~uartsendfull)) begin
				// Latch the data and byte select
				din <= axi4if.WDATA[7:0];
				we <= axi4if.WSTRB;
				axi4if.WREADY <= 1'b1;
				writestate <= 2'b01;
			end
		end
		2'b01: begin
			axi4if.WREADY <= 1'b0;
			if (axi4if.BREADY) begin
				axi4if.BVALID <= 1'b1;
				axi4if.BRESP <= 2'b00; // OKAY
				writestate <= 2'b10;
			end
		end
		default/*2'b10*/: begin
			axi4if.BVALID <= 1'b0;
			writestate <= 2'b00;
		end
	endcase
end

always @(posedge axi4if.ACLK) begin
	if (~axi4if.ARESETn) begin
		axi4if.ARREADY <= 1'b0;
		axi4if.RVALID <= 1'b0;
		axi4if.RRESP <= 2'b00;
	end else begin
		// Read address
		uartrcvre <= 1'b0;
		case (raddrstate)
			2'b00: begin
				if (axi4if.ARVALID) begin
					axi4if.ARREADY <= 1'b1;
					if (axi4if.ARADDR[3:0] == 4'h8) begin // Data I/O port
						uartrcvre <= 1'b1;
						raddrstate <= 2'b01;
					end else begin
						raddrstate <= 2'b10;
					end
				end
			end
			2'b01: begin
				// Master ready to accept
				if (axi4if.RREADY & uartrcvvalid) begin
					axi4if.ARREADY <= 1'b0;
					axi4if.RDATA <= {uartrcvdout, uartrcvdout, uartrcvdout, uartrcvdout};
					axi4if.RVALID <= 1'b1;
					//axi4if.RLAST <= 1'b1; // Last in burst
					raddrstate <= 2'b11; // Delay one clock for master to pull down ARVALID
				end
			end
			2'b10: begin
				// Master ready to accept
				if (axi4if.RREADY) begin
					if (axi4if.ARADDR[3:0] == 4'h4) // Byteavailable port
						axi4if.RDATA <= {31'd0, ~uartrcvempty};
					else /*if (axi4if.ARADDR[3:0] == 4'h0)*/ // Sendfifofull port
						axi4if.RDATA <= {31'd0, uartsendfull};
					axi4if.RVALID <= 1'b1;
					//axi4if.RLAST <= 1'b1; // Last in burst
					raddrstate <= 2'b11; // Delay one clock for master to pull down ARVALID
				end
			end
			default/*2'b11*/: begin
				// At this point master should have responded properly with ARVALID=0
				//axi4if.RLAST <= 1'b0;
				axi4if.ARREADY <= 1'b0;
				axi4if.RVALID <= 1'b0;
				raddrstate <= 2'b00;
			end
		endcase
	end
end

endmodule
