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
//JB:
// 2008-03-14		- moving beamcounter to a separate file
//					- pal/ntsc switching, NTSC doesn't use short/long line toggling,all lines are short like in PAL (227 CCK's)
//					- composite blanking use hblank which is combined with vblank

//beam counters and sync generator
module beamcounter
(
	input	clk,				//bus clock
	input	reset,				//reset
	input	interlace,			//interlace enable
	input	ntsc,				//ntsc mode switch
	input	[15:0]datain,		//bus data in
	output	reg [15:0]dataout,//bus data out
	input 	[8:1]regaddressin,//register address inputs
	output	reg [8:0]hpos,	//horizontal (low resolution) beam counter
	output	reg [10:0]vpos,	//vertical beam counter
	output	reg _hsync,		//horizontal sync
	output	reg _vsync,		//vertical sync
	output	blank,				//video blanking
	output	vbl,				//vertical blanking
	output	vblend,				//last line of vertival blanking
	output	eol,				//start of video line (active during last pixel of previous line) 
	output	eof					//start of video frame (active during last pixel of previous frame)
);


//local signals for beam counters and sync generator
reg		hblank;			//horizontal blanking
wire	vblank;			//vertical blanking

reg		lof;			//1=long frame (313 lines), 0=normal frame (312 lines)
reg		pal;			//pal mode switch
reg		lol;			//long line signal for NTSC compatibility

//register names and adresses		
parameter VPOSR = 9'h004;
parameter VHPOSR = 9'h006;
parameter BEAMCON0 = 9'h1DC;

parameter	hbstrt  = 17;			// horizontal blanking start
parameter	hsstrt  = 29;			// front porch = 1.6us (29)
parameter	hsstop  = 63;			// hsync pulse duration = 4.7us (63)
parameter	hbstop  = 92;			// back porch = 4.7us (103) shorter blanking for overscan visibility
parameter	hcenter = 254;			// position of vsync pulse during the long field of interlaced screen
parameter	htotal  = 453;			// line length = 227 colour clocks in PAL (in NTSC 227.5 colour clocks: not supported)
parameter	vsstrt  = 3;			//vertical sync start
parameter	vsstop  = 5;			// pal vsync width: 2.5 lines (NTSC: 3 lines - not implemented)
parameter	vbstrt  = 0;			//vertical blanking start

wire	[8:0]vtotal;		//total number of lines less one
wire	[8:0]vbstop;		//vertical blanking stop

assign	vtotal  = pal ? 312-1 : 262-1;	//total number of lines (PAL: 312 lines, NTSC: 262)
assign	vbstop  = pal ? 25 : 20;	//vertical blanking end (PAL 26 lines, NTSC vblank 21 lines)
//A4k test: first visible line $1A (PAL) or $15 (NTSC)
//sprites fetched on line $19 (PAL) or $14 (NTSC)

//--------------------------------------------------------------------------------------
//beamcounter read registers VPOSR and VHPOSR
always @(regaddressin or lof or vpos or hpos or ntsc)
	if(regaddressin[8:1]==VPOSR[8:1])
		dataout[15:0] = {lof,ntsc?7'h30:7'h20,lol,4'b0000,vpos[10:8]};
	else	if(regaddressin[8:1]==VHPOSR[8:1])
		dataout[15:0] = {vpos[7:0],hpos[8:1]};
	else
		dataout[15:0]=0;
		
//BEAMCON0 register
always @(posedge clk)
	if (reset)
		pal <= ~ntsc;
	else if (regaddressin[8:1] == BEAMCON0[8:1])
		pal <= datain[5];
		
//--------------------------------------------------------------------------------------

//horizontal beamcounter (runs @ clk frequency!)
always @(posedge clk)
	if (eol)
		hpos <= 0;
	else
		hpos <= hpos + 1;

//generate start of line signal
assign eol = hpos==htotal ? 1 : 0;

//long line signal (not used, only for better NTSC compatibility)
always @(posedge clk)
	if (eol)
		if (pal)
			lol <= 0;
		else
			lol <= ~lol;

//horizontal sync and horizontal blanking
always @(posedge clk)//sync
	if (hpos==hsstrt)//start of sync pulse (front porch = 1.69us)
		_hsync <= 0;
	else if (hpos==hsstop)//end of sync pulse	(sync pulse = 4.65us)
		_hsync <= 1;
		
always @(posedge clk)//blank
	if(hpos==hbstrt)//start of blanking (active line=51.88us)
		hblank <= 1;
	else if (hpos==hbstop)//end of blanking (back porch=5.78us)
		hblank <= vblank;

//--------------------------------------------------------------------------------------

//vertical beamcounter (triggered by eol signal from horizontal beamcounter)
always @(posedge clk)
	if (eof)
		vpos <= 0;
	else if (eol)
		vpos <= vpos + 1;

// lof - Long Frame signal
always @(posedge clk)
	if (eof)
		if (interlace)
			lof <= ~lof;	// interlace
		else
			lof <= 1;

reg	 xln;		//extra line (used in interlaced mode)
always @(posedge clk)
	if (eol)
		if (lof && vpos==vtotal)
			xln <= 1;
		else
			xln <= 0;
			
//generate end of frame signal
assign eof = (eol && vpos==vtotal && !lof) || (eol && xln && lof);

//vertical sync and vertical blanking
always @(posedge clk)
	if ((vpos==vsstrt && hpos==hsstrt && !lof) || (vpos==vsstrt && hpos==hcenter && lof))
		_vsync <= 0;
	else if ((vpos==vsstop && hpos==hcenter && !lof) || (vpos==vsstop+1 && hpos==hsstrt && lof))
		_vsync <= 1;


//vertical blanking end (last line)
assign vblend = vpos==vbstop ? 1 : 0;

assign vblank = vpos <= vbstop ? 1: 0;

//vbl output for sprite engine
assign vbl = vblank;

//--------------------------------------------------------------------------------------

//composite blanking
assign blank = hblank;

//--------------------------------------------------------------------------------------

endmodule