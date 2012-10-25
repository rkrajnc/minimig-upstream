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

module amber(	clk,vgaclk,dblscan,
			osdblank,osdpixel,
			redin,bluein,greenin,_hsyncin,_vsyncin,
			redout,blueout,greenout,_hsyncout,_vsyncout);
input 	clk;		   			//bus clock / lores pixel clock
input	vgaclk;				//VGA pixel clock
input	dblscan;				//enable VGA output (enable scandoubler)
input	osdblank;				//OSD overlay enable (blank normal video)
input	osdpixel;				//OSD pixel(video) data
input 	[3:0]redin; 			//red componenent video in
input 	[3:0]greenin;  		//green component video in
input 	[3:0]bluein;			//blue component video in
input	_hsyncin;				//horizontal synchronisation in
input	_vsyncin;				//vertical synchronisation in
output 	[3:0]redout; 			//red componenent video out
output 	[3:0]greenout;  		//green component video out
output 	[3:0]blueout;			//blue component video out
output	_hsyncout;			//horizontal synchronisation out
output	_vsyncout;			//vertical synchronisation out

//local signals
reg		_vsyncout; 			//registered output
reg		[25:0]linebuf[453:0];	//scan doubler line buffer
reg		[11:0]hresbuf;			//hires pixel buffer
reg		[9:0]addr;			//line buffer input address
reg		[25:0]vgadata;			//linebuffer output data
reg		_hsyncd;				//delayed _hsyncin
wire		_hcsync;				//horizontal/composite sync
wire		[3:0]redin2; 			//video data + osd overlay
wire		[3:0]greenin2;		    	//video data + osd overlay
wire		[3:0]bluein2;	 		//video data + osd overlay

//delayed version of _hsync
always @(posedge clk)
	_hsyncd<=_hsyncin;	

//OSD overlay
assign redin2[3:0]=(osdblank)?{osdpixel,osdpixel,osdpixel,osdpixel}:redin[3:0];
assign greenin2[3:0]=(osdblank)?{osdpixel,osdpixel,osdpixel,osdpixel}:greenin[3:0];
assign bluein2[3:0]=(osdblank)?4'b1111:bluein[3:0];

//latch data for hires pixel at falling edge of clk (hires is double pumped, see Denise)
always @(negedge clk)
	hresbuf[11:0]<={redin2[3:0],greenin2[3:0],bluein2[3:0]};

//video line input address counter and line counter
//counter is synchronised to leading edge of _hsyncin 
always @(posedge clk)
	if(!_hsyncin && _hsyncd)
		addr[9:0]<={~addr[9],9'b000000000};
	else
		addr[8:0]<=addr[8:0]+1;

//horizontal / composite sync control
assign _hcsync=(dblscan)?_hsyncin:(_hsyncin&_vsyncin);

//register vertical sync output
always @(posedge clk)
	if(dblscan)
		_vsyncout<=_vsyncin;//31kHz mode
	else
		_vsyncout<=1;//15kHz mode

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//28 MHz VGA part (clocked by vgaclk)
reg 		[3:0]redout; 		//registered output
reg 		[3:0]greenout;  	//registered output
reg 		[3:0]blueout;		//registered output
reg		_hsyncout;		//registered output
reg 		phd;				//used to detect line phase errors
reg		phe;				//true if line phase error detected
wire		eovl;			//end of vga video line
reg		[9:0]vgahorbeam;	//28MHz horizontal beam counter
reg		vce;				//28MHz vga clock enable

//clock enable control, if scandoubler is enabled (vgaenable==1)
//ce is always true, so that the circuitry runs a 31kHz linerate.
//if the scandoubler is disabled, vce toggles @ vgaclk/2, so
//that the circuitry runs at 15kHz linerate
always @(posedge vgaclk)
	if(dblscan)
		vce<=1;//31kHz mode
	else
		vce<=~vce;//15kHz mode

//line phase error detector for 31kHz mode
//line data (vgadata) is valid for 2 clocks
//on the second clock (vgahorbeam[0]==1), the phase is checked
//if it was equal during the scan phe=0. If the phase changed phe=1
//and the beamcounter is delayed by one clock
always @(posedge vgaclk)
	if(vce && vgahorbeam[0] && eovl)
	begin
		phd<=vgadata[0];
		phe<=0;
	end
	else if(vce && vgahorbeam[0] && (phd==vgadata[0]))
		phe<=1;

//VGA 28MHz horizontal beamcounter
always @(posedge vgaclk)
	if(vce && eovl && !phe)
		vgahorbeam[9:0]<=0;
	else	if (vce && !eovl)
		vgahorbeam[9:0]<=vgahorbeam[9:0]+1;

//detect end of vga line
assign eovl=(vgahorbeam[9:0]==907)?1:0;
		
//registered rgb output and horizontal sync output
always @(posedge vgaclk)
begin
	//red, green and blue
	if(vgahorbeam[0])
	begin
		redout[3:0]<=vgadata[25:22];
		greenout[3:0]<=vgadata[21:18];
		blueout[3:0]<=vgadata[17:14];
	end
	else
	begin
		redout[3:0]<=vgadata[13:10];
		greenout[3:0]<=vgadata[9:6];
		blueout[3:0]<=vgadata[5:2];
	end
	//horizontal synchronization
	_hsyncout<=vgadata[1];
end

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//line buffer
//this should instantiate a dual ported block ram
always @(posedge clk)
	linebuf[addr[8:0]]<={hresbuf,redin2[3:0],greenin2[3:0],bluein2[3:0],_hcsync,addr[9]};
always @(posedge vgaclk)
	if(vce && !vgahorbeam[0])
		vgadata<=linebuf[vgahorbeam[9:1]];

//--------------------------------------------------------------------------------------
endmodule
