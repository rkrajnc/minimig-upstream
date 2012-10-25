// Copyright 2006, 2007 Dennis van Weeren
//
// This file is part of Minimig
//
// Minimig is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// (at your option) any later version.
//
// Minimig is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//
//

//Master clock generator for minimig
//This module generates all necessary clocks from the 4.433619 PAL clock
//JB:
// 2008-03-01	- added ddl for generating in phase system clock with 28MHz clock

module clock_generator
(
	input	mclk,		//4.433619 MHz master clock input
	output	clk28m,	 	//28.37516 MHz clock output
	output 	clk, 		//7.09379  MHz clock output
	output 	clk90, 		//7.09379  MHz qudrature clock output
	output 	e		  	//0.709379 MHz clock enable output (clk domain pulse)
);

	reg		[3:0]ediv;	//used to generate e clock enable

	wire	pll_mclk;
	wire	pll_c28m;
	wire	dll_c28m;
	wire	dll_c7m;

	reg 	clk90_reg;		//quadrature clock buffer
   
   IBUFG mclk_buf ( .I(mclk), .O(pll_mclk) );	
	
	DCM #
	(
		.CLKDV_DIVIDE(2.0), // Divide by: 1.5,2.0,2.5,3.0,3.5,4.0,4.5,5.0,5.5,6.0,6.5,7.0,7.5,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0 or 16.0
		.CLKFX_DIVIDE(5),   // Can be any integer from 1 to 32
		.CLKFX_MULTIPLY(32), // Can be any integer from 2 to 32
		.CLKIN_DIVIDE_BY_2("FALSE"), // TRUE/FALSE to enable CLKIN divide by two feature
		.CLKIN_PERIOD(225.0),  // Specify period of input clock
		.CLKOUT_PHASE_SHIFT("NONE"), // Specify phase shift of NONE, FIXED or VARIABLE
		.CLK_FEEDBACK("NONE"),  // Specify clock feedback of NONE, 1X or 2X
		.DESKEW_ADJUST("SYSTEM_SYNCHRONOUS"), // SOURCE_SYNCHRONOUS, SYSTEM_SYNCHRONOUS or an integer from 0 to 15
		.DFS_FREQUENCY_MODE("LOW"),  // HIGH or LOW frequency mode for frequency synthesis
		.DLL_FREQUENCY_MODE("LOW"),  // HIGH or LOW frequency mode for DLL
		.DUTY_CYCLE_CORRECTION("TRUE"), // Duty cycle correction, TRUE or FALSE
		.FACTORY_JF(16'hC080),   // FACTORY JF values
		.PHASE_SHIFT(0),     // Amount of fixed phase shift from -255 to 255
		.STARTUP_WAIT("FALSE")   // Delay configuration DONE until DCM LOCK, TRUE/FALSE
	)
	pll
	(
		.CLKFX(pll_c28m),   // DCM CLK synthesis out (M/D)
		.CLKIN(pll_mclk)   // Clock input (from IBUFG, BUFG or DCM)
	);

	DCM #
	(
		.CLKDV_DIVIDE(4.0), // Divide by: 1.5,2.0,2.5,3.0,3.5,4.0,4.5,5.0,5.5,6.0,6.5,7.0,7.5,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0 or 16.0
		.CLKFX_DIVIDE(4),   // Can be any integer from 1 to 32
		.CLKFX_MULTIPLY(4), // Can be any integer from 2 to 32
		.CLKIN_DIVIDE_BY_2("FALSE"), // TRUE/FALSE to enable CLKIN divide by two feature
		.CLKIN_PERIOD(35.0),  // Specify period of input clock
		.CLKOUT_PHASE_SHIFT("NONE"), // Specify phase shift of NONE, FIXED or VARIABLE
		.CLK_FEEDBACK("1X"),  // Specify clock feedback of NONE, 1X or 2X
		.DESKEW_ADJUST("SYSTEM_SYNCHRONOUS"), // SOURCE_SYNCHRONOUS, SYSTEM_SYNCHRONOUS or an integer from 0 to 15
		.DFS_FREQUENCY_MODE("LOW"),  // HIGH or LOW frequency mode for frequency synthesis
		.DLL_FREQUENCY_MODE("LOW"),  // HIGH or LOW frequency mode for DLL
		.DUTY_CYCLE_CORRECTION("TRUE"), // Duty cycle correction, TRUE or FALSE
		.FACTORY_JF(16'hC080),   // FACTORY JF values
		.PHASE_SHIFT(0),     // Amount of fixed phase shift from -255 to 255
		.STARTUP_WAIT("FALSE")   // Delay configuration DONE until DCM LOCK, TRUE/FALSE
	)
	dll
	(
		.CLKIN(pll_c28m),	// Clock input (from IBUFG, BUFG or DCM)
		.CLK0(dll_c28m),	// 0 degree DCM CLK output
		.CLKDV(dll_c7m),	// Divided DCM CLK out (CLKDV_DIVIDE)
		.CLKFB(clk28m)		// DCM clock feedback
	);
	
	//global clock buffers
	BUFG clk28m_buf ( .I(dll_c28m), .O(clk28m) );
	BUFG clk_buf ( .I(dll_c7m), .O(clk) );
	BUFG clk90_buf ( .I(clk90_reg), .O(clk90) );
	
//quadrature clock 
always @(posedge clk28m)
	clk90_reg <= clk;

//generate e
always @(posedge clk)
	if (e)
		ediv <= 9;
	else
		ediv <= ediv - 1;
		
assign e = (ediv==4'b0000) ? 1 : 0;

endmodule
