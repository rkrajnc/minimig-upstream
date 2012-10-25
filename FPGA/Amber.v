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
// This is Amber 
// Amber is a scandoubler to allow connection to a VGA monitor. 
// In addition, it can overlay an OSD (on-screen-display) menu.
// Amber also has a pass-through mode in which
// the video output can be connected to an RGB SCART input.
// The meaning of _hsyncout and _vsyncout is then:
// _vsyncout is fixed high (for use as RGB enable on SCART input).
// _hysncout is composite sync output.
//
// 10-01-2006		-first serious version
// 11-01-2006		-done lot's of work, Amber is now finished
// 29-12-2006		-added support for OSD overlay
// JB:
// 26-02-2008	- synchronous 28MHz version
// 28-02-2008	- horizontal and vertical interpolation
// 02-03-2008	- hfilter/vfilter inputs added, unused inputs removed

module Amber
(	
	input	clk,
	input 	clk28m,
	input	[1:0]lr_filter,
	input	[1:0]hr_filter,
	input	hires,
	input	dblscan,				//enable VGA output (enable scandoubler)
	input	osdblank,				//OSD overlay enable (blank normal video)
	input	osdpixel,				//OSD pixel(video) data
	input 	[3:0]redin, 			//red componenent video in
	input 	[3:0]greenin,  		//green component video in
	input 	[3:0]bluein,			//blue component video in
	input	_hsyncin,				//horizontal synchronisation in
	input	_vsyncin,				//vertical synchronisation in
	output 	reg [3:0]redout, 		//red componenent video out
	output 	reg [3:0]greenout,  	//green component video out
	output 	reg [3:0]blueout,		//blue component video out
	output	reg _hsyncout,			//horizontal synchronisation out
	output	reg _vsyncout			//vertical synchronisation out
);

//local signals
reg 	[3:0]red_del;
reg 	[3:0]green_del;
reg 	[3:0]blue_del;

wire 	[4:0]red;
wire	[4:0]green;
wire 	[4:0]blue;

reg		_hsyncin_del;			//delayed horizontal synchronisation input
reg		hss;					//horizontal sync start

reg		hfilter;				//horizontal interpolation enable
reg		vfilter;				//vertical interpolation enable

//-----------------------------------------------------------------------------//

// local horizontal counters for scan doubling
reg		[10:0]hposin;		//line buffer write pointer
reg		[10:0]hposout;	//line buffer read pointer
//reg		[10:0]htotal;		//line length (for variable line length)

always @(posedge clk28m)
	_hsyncin_del <= _hsyncin;

//horizontal sync start	
always @(posedge clk28m)
	hss <= ~_hsyncin & _hsyncin_del;

// pixels delayed by one hires pixel for horizontal interpolation
always @(posedge clk28m)
	if (hposin[0])	//sampled at 14MHz (hires clock rate)
		begin
			red_del <= redin;
			green_del <= greenin;
			blue_del <= bluein;
		end

//horizontal interpolation
assign red	= hfilter ? redin + red_del : redin*2;
assign green = hfilter ? greenin + green_del : greenin*2;
assign blue	= hfilter ? bluein + blue_del : bluein*2;

// horizontal line length
//always @(posedge clk28m)
//	if (hss)
//		htotal <= hposin;

// line buffer write pointer
always @(posedge clk28m)
	if (hss)
		hposin <= 0;
	else
		hposin <= hposin + 1;

//line buffer read pointer
always @(posedge clk28m)
//	if (hss || hposout==htotal/2)//for variable line length use htotal/2
	if (hss || hposout==907)
		hposout <= 0;
	else
		hposout <= hposout + 1;

always @(posedge clk28m)
	if (hss)
		hfilter <= hires ? hr_filter[0] : lr_filter[0];		//horizontal interpolation enable

always @(posedge clk28m)
	if (hss)
		vfilter <= hires ? hr_filter[1] : lr_filter[1];		//vertical interpolation enable

reg	[17:0]lbf[1023:0];	// line buffer for scan doubling (there are 908/910 hires pixels in every line)
reg [17:0]lbfo;			// line buffer output register
reg [17:0]lbfo2;			// compensantion for one clock delay of the second line buffer
reg	[17:0]lbfd[1023:0];	// delayed line buffer for vertical interpolation
reg [17:0]lbfdo;			// delayed line buffer output register

// line buffer write
always @(posedge clk28m)
	lbf[hposin[10:1]] <= { _hsyncin, osdblank, osdpixel, red, green, blue };

//line buffer read
always @(posedge clk28m)
	lbfo <= lbf[hposout[9:0]];

//delayed line buffer write
always @(posedge clk28m)
	lbfd[hposout[9:0]] <= lbfo;

//delayed line buffer read
always @(posedge clk28m)
	lbfdo <= lbfd[hposout[9:0]];

//delayed line buffer pixel by one clock cycle
always @(posedge clk28m)
	lbfo2 <= lbfo;

// output pixel generation - OSD mixer and vertical interpolation
always @(posedge clk28m)
begin
		_hsyncout <= dblscan ? lbfo2[17] : _hsyncin&_vsyncin;
		
		if (~dblscan)
		begin  //pass through
			if (osdblank) //osd window
			begin
				if (osdpixel)	//osd text colour
				begin
					redout    <= 4'b1110;
					greenout  <= 4'b1110;
					blueout   <= 4'b1110;
				end
				else //osd background
				begin
					redout    <= redin / 2;
					greenout  <= greenin / 2;
					blueout   <= 4'b0100 + bluein / 2;
				end
			end
			else //no osd
			begin
					redout    <= redin;
					greenout  <= greenin;
					blueout   <= bluein;
			end
		end
		else
		begin
			if (lbfo2[16]) //osd window
			begin
				if (lbfo2[15])	//osd text colour
				begin
					redout    <= 4'b1110;
					greenout  <= 4'b1110;
					blueout   <= 4'b1110;
				end
				else	//osd background
					if (vfilter)
					begin //dimmed transparent background with vertical interpolation
						redout    <= ( lbfo2[14:10] + lbfdo[14:10] ) / 8;
						greenout  <= ( lbfo2[9:5] + lbfdo[9:5] ) / 8;
						blueout   <= 4'b0100 + ( lbfo2[4:0] + lbfdo[4:0] ) /8;
					end
					else
					begin //dimmed transparent background without vertical interpolation
						redout    <= lbfo2[14:11] / 2;
						greenout  <= lbfo2[9:6] / 2;
						blueout   <= 4'b0100 + lbfo2[4:1] / 2;
					end
			end
			else	//no osd
				if (vfilter)
				begin //vertical interpolation
					redout    <= ( lbfo2[14:10] + lbfdo[14:10] ) / 4;
					greenout  <= ( lbfo2[9:5] + lbfdo[9:5] ) / 4;
					blueout   <= ( lbfo2[4:0] + lbfdo[4:0] ) / 4;
				end
				else
				begin //no vertical interpolation
					redout    <= lbfo2[14:11];
					greenout  <= lbfo2[9:6];
					blueout   <= lbfo2[4:1];
				end
		end
end

// vsync buffer
always @(posedge clk28m)
	_vsyncout <= _vsyncin;

endmodule
