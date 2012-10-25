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
//-----------------------------------------------------------------------------
//JB:
// 2008-06-17	- added osd control by joy2
//				- spi8 rewritten to use spi clock
//				- added highlight (inversion) of selected osd line
//				- added user reset and reset to bootloader
//				- added memory and interpolation filters configuration
// 2008-07-28	- added JOYTEST register to make it compatible with ALPHA1/SIRIAX intro/trainer

module userio
(
	input 	clk,		    		//bus clock
	input 	reset,			   		//reset 
	input	sol,					//start of video line
	input	sof,					//start of video frame 
	input 	[8:1] regaddress,		//register adress inputs
	input	[15:0]datain,			//bus data in
	output	reg [15:0]dataout,	//bus data out
	inout	ps2mdat,				//mouse PS/2 data
	inout	ps2mclk,				//mouse PS/2 clk
	output	_fire0,					//joystick 0 fire output (to CIA)
	output	_fire1,					//joystick 1 fire output (to CIA)
	output	[2:0]user,			//user menu control [fire,up,down] (to Paula)
	input	[5:0]_joy1,			//joystick 1 in (default mouse port)
	input	[5:0]_joy2,			//joystick 2 in (default joystick port)
	input	[3:0]osdctrl,			//OSD control (minimig->host, [menu,select,down,up])
	input	_den,					//SPI enable
	input	din,		  			//SPI data in
	output	dout,	 				//SPI data out
	input	dclk,	  				//SPI clock
	output	osdblank,				//osd overlay, normal video blank output
	output	osdpixel,				//osd video pixel
	output	[1:0]lr_filter,
	output	[1:0]hr_filter,
	output	[1:0]memcfg,
	output	usrrst,					//user reset from osd module
	output	bootrst					//user reset to bootloader
);

//local signals	
reg		[5:0]_sjoy1;				//synchronized joystick 1 signals
reg		[5:0]_xjoy2;				//synchronized joystick 2 signals
wire	[5:0]_sjoy2;				//synchronized joystick 2 signals
wire	[15:0]mouse0dat;			//mouse counters
wire	_mleft,_mthird,_mright;	//mouse buttons
reg		joy1enable;					//joystick 1 enable (mouse/joy switch)
reg		joy2enable;					//joystick 2 enable when no osd
wire	osdenable;					//osd enable
wire	[3:0]xosdctrl;			//JB: osd control lines
wire	test_load;					//load test value to mouse counter 
wire	[15:0]test_data;			//mouse counter test value


//register names and adresses		
parameter JOY0DAT=9'h00a;
parameter JOY1DAT=9'h00c;
parameter POTINP=9'h016;
parameter JOYTEST=9'h036;

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
											   
//input synchronization of external signals
always @(posedge clk)
	_sjoy1[5:0]<=_joy1[5:0];	

always @(posedge clk)
	_xjoy2[5:0]<=_joy2[5:0];	

//port 2 joystick disable in osd
always @(posedge clk)
	if (osdenable)
		joy2enable <= 0;
	else if (_xjoy2[5:0] == 6'b11_1111)
		joy2enable <= 1;

assign _sjoy2[5:0] = joy2enable ? _xjoy2[5:0] : 6'b11_1111;

assign xosdctrl[3] = osdctrl[3] | (~_xjoy2[2] & ~_xjoy2[3]);
assign xosdctrl[2] = osdctrl[2] | (~_xjoy2[4] & ~joy2enable);
assign xosdctrl[1] = osdctrl[1] | (~_xjoy2[2] & _xjoy2[3] & ~joy2enable);
assign xosdctrl[0] = osdctrl[0] | (~_xjoy2[3] & _xjoy2[2] & ~joy2enable);

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
	else if(regaddress[8:1]==POTINP[8:1])//read mouse and joysticks extra buttons
		dataout[15:0]={1'b0,_sjoy2[5],3'b010,_mright&_sjoy1[5],1'b0,_mthird,8'b00000000};
	else
		dataout[15:0]=16'h0000;

//assign fire outputs to cia A
assign _fire1=_sjoy2[4];
assign _fire0=_sjoy1[4]&_mleft;

//assign user interface control signals
assign user[2:0]=~_sjoy2[4:2];

//JB: some trainers writes to JOYTEST register to reset current mouse counter
assign test_load = regaddress[8:1]==JOYTEST[8:1] ? 1 : 0;
assign test_data = datain[15:0];

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//instantiate mouse controller
ps2mouse pm1
(
	.clk(clk),
	.reset(reset),
	.ps2mdat(ps2mdat),
	.ps2mclk(ps2mclk),
	.ycount(mouse0dat[15:8]),
	.xcount(mouse0dat[7:0]),
	._mleft(_mleft),
	._mthird(_mthird),
	._mright(_mright),
	.test_load(test_load),
	.test_data(test_data)
);

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------


//instantiate osd controller
osd	osd1
(
	.clk(clk),
	.reset(reset),
	.sol(sol),
	.sof(sof),
	.osdctrl(xosdctrl),
	._den(_den),
	.din(din),
	.dout(dout),
	.dclk(dclk),
	.osdblank(osdblank),
	.osdpixel(osdpixel),
	.osdenable(osdenable),
	.lr_filter(lr_filter),
	.hr_filter(hr_filter),
	.memcfg(memcfg),
	.usrrst(usrrst),
	.bootrst(bootrst)
);

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//on screen display controller
module osd
(
	input 	clk,		    	//pixel clock
	input	reset,				//reset
	input	sol,				//start of video line
	input	sof,				//start of video frame 
	input	[3:0]osdctrl,		//OSD control (minimig->host, [menu,select,down,up])
	input	_den,				//SPI enable
	input	din,		  		//SPI data in
	output	dout,	 			//SPI data out
	input	dclk,	  			//SPI clock
	output	osdblank,			//osd overlay, normal video blank output
	output	osdpixel,			//osd video pixel
	output	osdenable,			//osd enable
	output	reg [1:0]lr_filter,
	output	reg [1:0]hr_filter,
	output	reg [1:0]memcfg,
	output	usrrst,
	output	bootrst
);

//local signals
reg		[8:0]horbeam;			//horizontal beamcounter
reg		[8:0]verbeam;			//vertical beamcounter
reg		[7:0]osdbuf[1023:0];	//osd video buffer
wire	osdframe;				//true if beamcounters within osd frame
reg		[7:0]bufout;			//osd buffer read data
reg 	osdenable1;				//osd display enable 1
reg 	osdenable2;				//osd display enable 2 (synchronized to start of frame)
reg 	[9:0]wraddr;			//osd buffer write address
wire	[7:0]wrdat;			//osd buffer write data
wire	wren;					//osd buffer write enable

reg		[3:0]highlight;		//highlighted line number
reg		invert;					//invertion of highlighted line

//--------------------------------------------------------------------------------------
//OSD video generator
//--------------------------------------------------------------------------------------

//osd local horizontal beamcounter
always @(posedge clk)
	if (sol)
		horbeam <= 0;
	else
		horbeam <= horbeam + 1;

//osd local vertical beamcounter
always @(posedge clk)
	if (sof)
		verbeam<=0;
	else if (sol)
		verbeam <= verbeam + 1;

//--------------------------------------------------------------------------------------
//generate osd video frame
reg	hframe,vframe;

//horizontal part..
always @(posedge clk)
	if (horbeam[8])
		hframe <= 0;
	else if (horbeam[7])
		hframe <= 1;

//vertical part..
always @(posedge clk)
	if (verbeam[7] && ~verbeam[6])
		vframe <= 1;
	else if (verbeam[0])
		vframe <= 0;

//combine..
assign osdframe = vframe & hframe & osdenable2;

always @(posedge clk)
	if (~highlight[3] && verbeam[5:3]==highlight[2:0] && ~verbeam[6])
		invert <= 1;
	else if (verbeam[0])
		invert <= 0;

//--------------------------------------------------------------------------------------

//assign osd blank and pixel outputs
assign osdpixel = invert ^ bufout[verbeam[2:0]];
assign osdblank = osdframe;

//--------------------------------------------------------------------------------------
//video buffer
//--------------------------------------------------------------------------------------

//dual ported osd video buffer
//video buffer is 1024*8
//this buffer should be a single blockram
always @(posedge clk)//input part
	if (wren)
		osdbuf[wraddr[9:0]] <= wrdat[7:0];
		
always @(posedge clk)//output part
	bufout[7:0] <= osdbuf[{verbeam[5:3],horbeam[6:0]}];

//--------------------------------------------------------------------------------------
//interface to host
//--------------------------------------------------------------------------------------
wire	rx;
wire	cmd;
reg 	[2:0]spicmd;		//spi command

//instantiate spi interface
spi8 spi0
(
	.clk(clk),
	.scs(~_den),
	.sdi(din),
	.sdo(dout),
	.sck(dclk),
	.in({4'b0000,osdctrl[3:0]}),
	.out(wrdat[7:0]),
	.rx(rx),
	.cmd(cmd)
);

//command latch
// commands are:
//
// 8'b00000000 	nop
// 8'b00100NNN 	write data to osd buffer line <NNN>
// 8'b01000000	disable displaying of osd
// 8'b01100000	enable displaying of osd
// 8'b10000000	reset Minimig
// 8'b10100000	read osdctrl (controls for osd)
// 8'b1110HHLL	set interpolation filter status
// 8'b111100MM	set memory configuration

always @(posedge clk)
	if (rx && cmd)
		spicmd <= wrdat[7:5];

//filter configuration
always @(posedge clk)
	if (rx && cmd && wrdat[7:4]==4'b1110)
		{hr_filter[1:0],lr_filter[1:0]} <= wrdat[3:0];

//memory configuration
always @(posedge clk)
	if (rx && cmd && wrdat[7:4]==4'b1111)
		memcfg[1:0] <= wrdat[1:0];

//address counter and buffer write control (write line <NNN> command)
always @(posedge clk)
	if (rx && cmd && wrdat[7:5]==3'b001)//set linenumber from incoming command byte
		wraddr[9:0] <= {wrdat[2:0],7'b0000000};
	else if (rx)	//increment for every data byte that comes in
		wraddr[9:0] <= wraddr[9:0] + 1;

always @(posedge clk)
	if (~osdenable1)
		highlight <= 4'b1000;
	else if (rx && cmd && wrdat[7:4]==4'b0011)
		highlight <= wrdat[3:0];
		
//disable/enable osd display
always @(posedge clk)
begin
	if(spicmd[2:0]==3'b010)//disable
		osdenable1 <= 0;
	else if(spicmd[2:0]==3'b011)//enable
		osdenable1 <= 1;
end

//synchronize osdenable 1 to start-of-frame
always @(posedge clk)
	osdenable2 <= osdenable1;
	
assign osdenable = osdenable2;

assign wren = rx && ~cmd && spicmd==3'b001 ? 1 : 0;

//user reset request (from osd menu)		
assign usrrst = rx && cmd && wrdat[7:5]==3'b100 ? 1 : 0;

//reset to bootloader
assign bootrst = rx && cmd && wrdat[7:5]==3'b100 && wrdat[0] ? 1 : 0;

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
module spi8
(
	input 	clk,		    //pixel clock
	input	scs,			//SPI chip select
	input	sdi,		  	//SPI data in
	output	sdo,	 		//SPI data out
	input	sck,	  		//SPI clock
	input	[7:0]in,		//parallel input data
	output	[7:0]out,		//parallel output data
	output	reg rx,		//byte received
	output	reg cmd			//first byte received
);

//locals
reg [2:0]bit_cnt;		//bit counter
reg [7:0]sdi_reg;		//input shift register	(rising edge of SPI clock)
reg sdo_reg;			//output shift register	 (falling edge of SPI clock)

reg new_byte;			//new byte (8 bits) received
reg rx_sync;			//synchronization to clk (first stage)
reg first_byte;		//first byte is going to be received

//------ input shift register ------//
always @(posedge sck)
		sdi_reg <= {sdi_reg[6:0],sdi};

assign out = sdi_reg;

//------ receive bit counter ------//
always @(posedge sck or negedge scs)
	if (~scs)
		bit_cnt <= 0;					//always clear bit counter when CS is not active
	else
		bit_cnt <= bit_cnt + 1;		//increment bit counter when new bit has been received

//----- rx signal ------//
//this signal goes high for one clk clock period just after new byte has been received
//it's synchronous with clk, output data shouldn't change when rx is active
always @(posedge sck or posedge rx)
	if (rx)
		new_byte <= 0;		//cleared asynchronously when rx is high (rx is synchronous with clk)
	else if (bit_cnt==7)
		new_byte <= 1;		//set when last bit of a new byte has been just received

always @(negedge clk)
	rx_sync <= new_byte;	//double synchronization to avoid metastability

always @(posedge clk)
	rx <= rx_sync;			//synchronous with clk

//------ cmd signal generation ------//
//this signal becomes active after reception of first byte
//when any other byte is received it's deactivated indicating data bytes
always @(posedge sck or negedge scs)
	if (~scs)
		first_byte <= 1;		//set when CS is not active
	else if (bit_cnt==7)
		first_byte <= 0;		//cleared after reception of first byte

always @(posedge sck)
	if (bit_cnt==7)
		cmd <= first_byte;		//active only when first byte received
	
//------ serial data output register ------//
always @(negedge sck)	//output change on falling SPI clock
	sdo_reg <= in[~bit_cnt[1:0]];

//------ SPI output signal ------//
assign sdo = scs & sdo_reg;	//force zero if SPI not selected

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//PS2 mouse controller.
//This module decodes the standard 3 byte packet of an PS/2 compatible 2 or 3 button mouse.
//The module also automatically handles power-up initailzation of the mouse.
module ps2mouse
(
	input 	clk,		    	//bus clock
	input 	reset,			   	//reset 
	inout	ps2mdat,			//mouse PS/2 data
	inout	ps2mclk,			//mouse PS/2 clk
	output	reg [7:0]ycount,	//mouse Y counter
	output	reg [7:0]xcount,	//mouse X counter
	output	reg _mleft,		//left mouse button output
	output	reg _mthird,		//third(middle) mouse button output
	output	reg _mright,		//right mouse button output
	input	test_load,			//load test value to mouse counter
	input	[15:0]test_data	//mouse counter test value
);

//local signals
reg		mclkout; 				//mouse clk out
wire	mdatout;				//mouse data out
reg		mdatb,mclkb,mclkc;	//input synchronization	

reg		[10:0]mreceive;		//mouse receive register	
reg		[11:0]msend;			//mouse send register
reg		[15:0]mtimer;			//mouse timer
reg		[2:0]mstate;			//mouse current state
reg		[2:0]mnext;			//mouse next state

wire	mclkneg;				//negative edge of mouse clock strobe
reg		mrreset;				//mouse receive reset
wire	mrready;				//mouse receive ready;
reg		msreset;				//mosue send reset
wire	msready;				//mouse send ready;
reg		mtreset;				//mouse timer reset
wire	mtready;				//mouse timer ready	 
wire	mthalf;					//mouse timer somewhere halfway timeout
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
	else if (test_load) //test value preload
		{ycount[7:2],xcount[7:2]} <= {test_data[15:10],test_data[7:2]};
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

