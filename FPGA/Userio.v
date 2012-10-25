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
// This is the user IO module
// joystick signals are _joy[5:0]=[fire2,fire,up,down,left,right];
//
// 16-10-2005		-started coding
// 17-10-2005		-added proper reset for mouse buttons/counters
//				-improved mouse startup timing
// 22-11-2005		-added joystick 1
// 05-02-2006		-unused buttons of joystick port 2 are now high
// 06-02-2006		-cleaned up code
//				-added user output
// 27-12-2006		-added joystick port 1 and automatic joystick/mouse switch
//				-started coding osd display
// 28-12-2006		-more osd display work done
// 29-12-2006		-fixed some bugs in osd module
// 30-12-2006		-cleaned up osd module, added osdctrl input

module userio(	clk,reset,sol,sof,regaddress,datain,dataout,
			ps2mdat,ps2mclk,_fire0,_fire1,user,_joy1,_joy2,
			osdctrl,_den,din,dout,dclk,osdblank,osdpixel);
input 	clk;		    			//bus clock
input 	reset;			   	//reset 
input	sol;					//start of video line
input	sof;					//start of video frame 
input 	[8:1] regaddress;		//register adress inputs
input	[15:0]datain;			//bus data in
output	[15:0]dataout;			//bus data out
inout	ps2mdat;				//mouse PS/2 data
inout	ps2mclk;				//mouse PS/2 clk
output	_fire0;				//joystick 0 fire output (to CIA)
output	_fire1;				//joystick 1 fire output (to CIA)
output	[2:0]user;			//user menu control [fire,up,down] (to Paula)
input	[5:0]_joy1;			//joystick 1 in (default mouse port)
input	[5:0]_joy2;			//joystick 2 in (default joystick port)
input	[3:0]osdctrl;			//OSD control (minimig->host, [menu,select,down,up])
input	_den;				//SPI enable
input	din;		  			//SPI data in
output	dout;	 			//SPI data out
input	dclk;	  			//SPI clock
output	osdblank;				//osd overlay, normal video blank output
output	osdpixel;				//osd video pixel


//local signals	
reg		[15:0]dataout;			//see above							   
reg		[5:0]_sjoy1;			//synchronized joystick 1  signals
reg		[5:0]_sjoy2;			//synchronized joystick 2  signals
wire		[15:0]mouse0dat;		//mouse counters
wire		_mleft,_mthird,_mright;	//mouse buttons
reg		joy1enable;			//joystick 1 enable (mouse/joy switch)


//register names and adresses		
parameter JOY0DAT=9'h00a;
parameter JOY1DAT=9'h00c;
parameter POTGOR=9'h016;

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
											   
//input synchronization of external signals
always @(posedge clk)
begin
	_sjoy1[5:0]<=_joy1[5:0];				
	_sjoy2[5:0]<=_joy2[5:0];				
end

//port 1 automatic mouse/joystick switch
always @(posedge clk)
	if(!_mleft || reset)//when left mouse button pushed, switch to mouse (default)
		joy1enable=0;
	else if(!_sjoy1[4])//when joystick 1 fire pushed, switch to joystick
		joy1enable=1;

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//data output multiplexer
always @(regaddress or joy1enable or _sjoy1 or mouse0dat or _sjoy2 or _mright or _mthird)
	if((regaddress[8:1]==JOY0DAT[8:1]) && joy1enable)//read port 1 joystick
		dataout[15:0]={6'b000000,~_sjoy1[1],_sjoy1[3]^_sjoy1[1],6'b000000,~_sjoy1[0],_sjoy1[2]^_sjoy1[0]};
	else if(regaddress[8:1]==JOY0DAT[8:1])//read port 1 mouse
		dataout[15:0]=mouse0dat[15:0];
	else if(regaddress[8:1]==JOY1DAT[8:1])//read port 2 joystick
		dataout[15:0]={6'b000000,~_sjoy2[1],_sjoy2[3]^_sjoy2[1],6'b000000,~_sjoy2[0],_sjoy2[2]^_sjoy2[0]};
	else if(regaddress[8:1]==POTGOR[8:1])//read mouse and joysticks extra buttons
		dataout[15:0]={1'b0,_sjoy2[5],3'b010,_mright&_sjoy1[5],1'b0,_mthird,8'b00000000};
	else
		dataout[15:0]=16'h0000;

//assign fire outputs to cia A
assign _fire1=_sjoy2[4];
assign _fire0=_sjoy1[4]&_mleft;

//assign user interface control signals
assign user[2:0]=~_sjoy2[4:2];

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//instantiate mouse controller
ps2mouse pm1(	.clk(clk),
			.reset(reset),
			.ps2mdat(ps2mdat),
			.ps2mclk(ps2mclk),
			.ycount(mouse0dat[15:8]),
			.xcount(mouse0dat[7:0]),
			._mleft(_mleft),
			._mthird(_mthird),
			._mright(_mright)	);

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------


//instantiate osd controller
osd	osd1 (	.clk(clk),
			.sol(sol),
			.sof(sof),
			.osdctrl(osdctrl),
			._den(_den),
			.din(din),
			.dout(dout),
			.dclk(dclk),
			.osdblank(osdblank),
			.osdpixel(osdpixel)			);

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//on screen display controller
module osd(clk,sol,sof,osdctrl,_den,din,dout,dclk,osdblank,osdpixel);
input 	clk;		    			//pixel clock
input	sol;					//start of video line
input	sof;					//start of video frame 

input	[3:0]osdctrl;			//OSD control (minimig->host, [menu,select,down,up])
input	_den;				//SPI enable
input	din;		  			//SPI data in
output	dout;	 			//SPI data out
input	dclk;	  			//SPI clock

output	osdblank;				//osd overlay, normal video blank output
output	osdpixel;				//osd video pixel

//local signals
reg		[8:0]horbeam;			//horizontal beamcounter
reg		[8:0]verbeam;			//vertical beamcounter
reg		[7:0]osdbuf[1023:0];	//osd video buffer
wire		osdframe;				//true if beamcounters within osd frame
reg		[7:0]bufout;			//osd buffer read data
reg 		osdenable1;			//osd display enable 1
reg 		osdenable2;			//osd display enable 2 (synchronized to start of frame)
reg 		[9:0]wraddr;			//osd buffer write address
wire		[7:0]wrdat;			//osd buffer write data
wire		wren;				//osd buffer write enable

//--------------------------------------------------------------------------------------
//OSD video generator
//--------------------------------------------------------------------------------------

//osd local horizontal beamcounter
always @(posedge clk)
	if(sol)
		horbeam<=0;
	else
		horbeam<=horbeam+1;

//osd local vertical beamcounter
always @(posedge clk)
	if(sof)
		verbeam<=0;
	else if(sol)
		verbeam<=verbeam+1;

//--------------------------------------------------------------------------------------
//generate osd video frame
reg	hframe,vframe;

//horizontal part..
always @(posedge clk)
	if(horbeam[8])
		hframe<=0;
	else if(horbeam[7])
		hframe<=1;

//vertical part..
always @(posedge clk)
	if(verbeam[7]&&verbeam[6])
		vframe<=0;
	else if(verbeam[7])
		vframe<=1;

//combine..
assign osdframe=vframe&hframe&osdenable2;

//--------------------------------------------------------------------------------------

//assign osd blank and pixel outputs
assign osdpixel=bufout[verbeam[2:0]];
assign osdblank=osdframe;

//--------------------------------------------------------------------------------------
//video buffer
//--------------------------------------------------------------------------------------

//dual ported osd video buffer
//video buffer is 1024*8
//this buffer should be a single blockram
always @(posedge clk)//input part
	if(wren)
		osdbuf[wraddr[9:0]]<=wrdat[7:0];
always @(posedge clk)//output part
	bufout[7:0]<=osdbuf[{verbeam[5:3],horbeam[6:0]}];

//--------------------------------------------------------------------------------------
//interface to host
//--------------------------------------------------------------------------------------
wire	strobe,en;
reg [2:0]spicmd;		//spi command


//instantiate spi interface
spi8 spi0 (	.clk(clk),
			._den(_den),
			.din(din),
			.dout(dout),
			.dclk(dclk),
			.in({4'b0000,osdctrl[3:0]}),
			.out(wrdat[7:0]),
			.strobe(strobe),
			.en(en)	);


//command latch
// commands are:
//
// 8'b00000000 	nop
// 8'b00100NNN 	write data to osd buffer line <NNN>
// 8'b01000000		disable displaying of osd
// 8'b01100000		enable displaying of osd
// 8'b10000000		reset Minimig
// 8'b10100000		read osdctrl (controls for osd)
always @(posedge clk)
	if(!en)//spi idle, clear command
		spicmd<=3'b000;
	else if(strobe && spicmd[2:0]==3'b000)//first byte to come in through spi is command
		spicmd<=wrdat[7:5];

//address counter and buffer write control (write line <NNN> command)
always @(posedge clk)
	if(wren)//increment for every data byte that comes in
		wraddr[9:0]<=wraddr[9:0]+1;
	else	if(strobe && spicmd[2:0]==3'b000)//set linenumber from incoming command byte
		wraddr[9:0]<={wrdat[2:0],7'b0000000};
assign wren=(strobe && spicmd[2:0]==3'b001)?1:0;

//disable/enable osd display
always @(posedge clk)
begin
	if(spicmd[2:0]==3'b010)//disable
		osdenable1<=0;
	else if(spicmd[2:0]==3'b011)//enable
		osdenable1<=1;
end

//synchronize osdenable 1 to start-of-frame
always @(posedge clk)
	osdenable2<=osdenable1;

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//SPI interface module (8 bits)
//this is a slave module, clock is controlled by host
//clock is high when bus is idle
//ingoing data is sampled at the positive clock edge
//outgoing data is shifted/changed at the negative clock edge
//msb is sent first
//         ____   _   _   _   _
//dclk   ->    |_| |_| |_| |_|
//data   ->     777 666 555 444
//sample ->      ^   ^   ^   ^
//strobe is asserted at the end of every byte and signals that new data must
//be registered at the out output. At the same time, new data is read from the in input.
//The data at input in is also sent as the first byte after _den is asserted (without strobe!). 
module spi8(clk,_den,din,dout,dclk,in,out,strobe,en);
input 	clk;		    			//pixel clock
input	_den;				//SPI enable
input	din;		  			//SPI data in
output	dout;	 			//SPI data out
input	dclk;	  			//SPI clock
input	[7:0]in;				//parallel input data
output	[7:0]out;				//parallel output data
output	strobe;				//parallel strobe
output	en;					//SPI enable, true if we are addressed

//local signals
reg	_den2,din2,dclk2,dclk3;		//synchronized versions of input signals
wire	dclkpos,dclkneg;			//SPI clock negative/positive edge strobes
reg	[7:0]dshift;				//SPI serial-parallel-serial shifter
reg	doutl;					//dout register
reg	[3:0]dcnt;				//bit counter

//input synchronisation
always @(posedge clk)
begin
	_den2<=_den;
	din2<=din;
	dclk2<=dclk;
	dclk3<=dclk2;
end

//SPI clock positive edge detect
assign dclkpos=dclk2&(~dclk3);

//SPI clock negative edge detect
assign dclkneg=(~dclk2)&dclk3;

//dout control
assign dout=(!_den2)?doutl:1'b0;

//assign parallel output data
assign out[7:0]=dshift[7:0];

//assign en
assign en=~_den2;

//serial-parallel / parallel-serial converter
always @(posedge clk)
begin
	if(dclkneg)//data out at negative edge
		doutl<=dshift[7];
	if(_den2 || strobe)//load new data to send out
		dshift[7:0]<=in[7:0];
	else if(dclkpos)//data in at positive edge
		dshift[7:0]<={dshift[6:0],din2};
end

//bit counter and strobe
always @(posedge clk)
	if(_den2 || strobe)
		dcnt[3:0]<=0;
	else if(dclkpos)
		dcnt[3:0]<=dcnt[3:0]+1;
assign strobe=dcnt[3];


endmodule


















//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//PS2 mouse controller.
//This module decodes the standard 3 byte packet of an PS/2 compatible 2 or 3 button mouse.
//The module also automatically handles power-up initailzation of the mouse.
module ps2mouse(clk,reset,ps2mdat,ps2mclk,ycount,xcount,_mleft,_mthird,_mright);
input 	clk;		    			//bus clock
input 	reset;			   	//reset 
inout	ps2mdat;				//mouse PS/2 data
inout	ps2mclk;				//mouse PS/2 clk
output	[7:0]ycount;			//mouse Y counter
output	[7:0]xcount;			//mouse X counter
output	_mleft;				//left mouse button output
output	_mthird;				//third(middle) mouse button output
output	_mright;				//right mouse button output

//local signals
reg		[7:0]ycount;			//see above
reg		[7:0]xcount;			//see above
reg		_mleft;				//see above
reg		_mthird;				//see above
reg		_mright;				//see above

reg		mclkout; 				//mouse clk out
wire		mdatout;				//mouse data out
reg		mdatb,mclkb,mclkc;		//input synchronization	

reg		[10:0]mreceive;		//mouse receive register	
reg		[11:0]msend;			//mouse send register
reg		[15:0]mtimer;			//mouse timer
reg		[2:0]mstate;			//mouse current state
reg		[2:0]mnext;			//mouse next state

wire		mclkneg;				//negative edge of mouse clock strobe
reg		mrreset;				//mouse receive reset
wire		mrready;				//mouse receive ready;
reg		msreset;				//mosue send reset
wire		msready;				//mouse send ready;
reg		mtreset;				//mouse timer reset
wire		mtready;				//mouse timer ready	 
wire		mthalf;				//mouse timer somewhere halfway timeout
reg		[1:0]mpacket;			//mouse packet byte valid number

//bidirectional open collector IO buffers
assign ps2mclk=(mclkout)?1'bz:1'b0;
assign ps2mdat=(mdatout)?1'bz:1'b0;

//input synchronization of external signals
always @(posedge clk)
begin
	mdatb<=ps2mdat;
	mclkb<=ps2mclk;
	mclkc<=mclkb;
end						

//detect mouse clock negative edge
assign mclkneg=mclkc&(~mclkb);

//PS2 mouse input shifter
always @(posedge clk)
	if(mrreset)
		mreceive[10:0]<=11'b11111111111;
	else if(mclkneg)
		mreceive[10:0]<={mdatb,mreceive[10:1]};
assign mrready=~mreceive[0];

//PS2 mouse send shifter
always @(posedge clk)
	if(msreset)
		msend[11:0]<=12'b110111101000;
	else if(!msready && mclkneg)
		msend[11:0]<={1'b0,msend[11:1]};
assign msready=(msend[11:0]==12'b000000000001)?1:0;
assign mdatout=msend[0];

//PS2 mouse timer
always @(posedge clk)
	if(mtreset)
		mtimer[15:0]<=16'h0000;
	else
		mtimer[15:0]<=mtimer[15:0]+1;
assign mtready=(mtimer[15:0]==16'hffff)?1:0;
assign mthalf=mtimer[11];

//PS2 mouse packet decoding and handling
always @(posedge clk)
begin
	if(reset)//reset
	begin
		{_mthird,_mright,_mleft}<=3'b111;
		xcount[7:0]<=8'h00;	
		ycount[7:0]<=8'h00;
	end
	else if(mpacket==1)//buttons
		{_mthird,_mright,_mleft}<=~mreceive[3:1];
	else if(mpacket==2)//delta X movement
		xcount[7:0]<=xcount[7:0]+mreceive[8:1];
	else if(mpacket==3)//delta Y movement
		ycount[7:0]<=ycount[7:0]-mreceive[8:1];
end

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//PS2 mouse state machine
always @(posedge clk)
	if(reset || mtready)//master reset OR timeout
		mstate<=0;
	else 
		mstate<=mnext;
always @(mstate or mthalf or msready or mrready or mreceive)
begin
	case(mstate)
		0://initialize mouse phase 0, start timer
			begin
				mclkout=1;
				mrreset=0;
				mtreset=1;
				msreset=0;
				mpacket=0;
				mnext=1;
			end

		1://initialize mouse phase 1, hold clk low and reset send logic
			begin
				mclkout=0;
				mrreset=0;
				mtreset=0;
				msreset=1;
				mpacket=0;
				if(mthalf)//clk was low long enough, go to next state
					mnext=2;
				else
					mnext=1;
			end

		2://initialize mouse phase 2, send 'enable data reporting' command to mouse
			begin
				mclkout=1;
				mrreset=1;
				mtreset=0;
				msreset=0;
				mpacket=0;
				if(msready)//command set, go get 'ack' byte
					mnext=5;
				else
					mnext=2;
			end

		3://get first packet byte
			begin
				mclkout=1;
				mtreset=1;
				msreset=0;
				if(mrready)//we got our first packet byte
				begin
					mpacket=1;
					mrreset=1;
					mnext=4;
 				end
				else//we are still waiting				
 				begin
					mpacket=0;
					mrreset=0;
					mnext=3;
				end
			end

		4://get second packet byte
			begin
				mclkout=1;
				mtreset=0;
				msreset=0;
				if(mrready)//we got our second packet byte
				begin
					mpacket=2;
					mrreset=1;
					mnext=5;

				end
				else//we are still waiting				
 				begin
					mpacket=0;
					mrreset=0;
					mnext=4;
				end
			end

		5://get third packet byte (or get 'ACK' byte..)
			begin
				mclkout=1;
				mtreset=0;
				msreset=0;
				if(mrready)//we got our third packet byte
				begin
					mpacket=3;
					mrreset=1;
					mnext=3;

				end
				else//we are still waiting				
 				begin
					mpacket=0;
					mrreset=0;
					mnext=5;
				end
			end
 
		default://we should never come here
			begin
				mclkout=1'bx;
				mrreset=1'bx;
				mtreset=1'bx;
				msreset=1'bx;
				mpacket=2'bxx;
				mnext=0;
			end

	endcase
end

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

endmodule

