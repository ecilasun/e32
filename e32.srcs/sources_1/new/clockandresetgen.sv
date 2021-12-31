module clockandresetgen(
	input wire sys_clock_i,
	output wire wallclock,
	output wire cpuclock,
	output wire uartbaseclock,
	output wire spibaseclock,
	output wire clk_ddr_w,
	output wire clk_ddr_dqs_w,
	output wire clk_ref_w,
	//output wire gpuclock,
	//output wire videoclock,
	output logic devicereset = 1'b1 );

wire centralclocklocked, ddr3clklocked;//, videoclocklocked;

centralclockgen CentralClock(
	.clk_in1(sys_clock_i),
	.wallclock(wallclock),
	.cpuclock(cpuclock),
	.uartbaseclock(uartbaseclock),
	.spibaseclock(spibaseclock),
	.locked(centralclocklocked) );
	
/*videoclockgen VideoClocks(
	.clk_in1(sys_clock_i),
	.gpuclock(gpuclock),
	.videoclock(videoclock),
	.locked(videoclocklocked) );*/

ddr3clk DDR3MemoryClock(
	.clk_in1(sys_clock_i),
	.clk_ddr_w(clk_ddr_w),
	.clk_ddr_dqs_w(clk_ddr_dqs_w),
	.clk_ref_w(clk_ref_w),
	.locked(ddr3clklocked));

// Hold reset until clocks are locked
//wire internalreset = ~(centralclocklocked & videoclocklocked & ddr3clklocked);
wire internalreset = ~(centralclocklocked & ddr3clklocked);

// Delayed reset post-clock-lock
logic [3:0] resetcountdown = 4'hF;
always @(posedge wallclock) begin // Using slowest clock
	if (internalreset) begin
		resetcountdown <= 4'hF;
		devicereset <= 1'b1;
	end else begin
		if (/*busready &&*/ (resetcountdown == 4'h0))
			devicereset <= 1'b0;
		else
			resetcountdown <= resetcountdown - 4'h1;
	end
end

endmodule
