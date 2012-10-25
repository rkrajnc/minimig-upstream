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
// This is the floppy disk controller (part of Paula)
//
// 23-10-2005		-started coding
// 24-10-2005		-done lots of work
// 13-11-2005		-modified fifo to use block ram
//				-done lots of work
// 14-11-2005		-done more work
// 19-11-2005		-added wordsync logic
// 20-11-2005		-finished core floppy disk interface
//				-added disk interrupts
//				-added floppy control signal emulation
// 21-11-2005		-cleaned up code a bit
// 27-11-2005		-den and sden are now active low (_den and _sden)
//				-fixed bug in parallel/serial converter
//				-fixed more bugs
// 02-12-2005		-removed dma abort function
// 04-12-2005		-fixed bug in fifo empty signalling
// 09-12-2005		-fixed dsksync handling	
//				-added protection against stepping beyond track limits
// 10-12-2005		-fixed some more bugs
// 11-12-2005		-added dout output enable to allow SPI bus multiplexing
// 12-12-2005		-fixed major bug, due error in statemachine, multiple interrupts were requested
//				 after a DMA transfer, this could lock up the whole machine
// 				-enable line disconnected  --> this module still needs a lot of work
// 27-12-2005		-cleaned up code, this is it for now
// 07-01-2005		-added dmas
// 15-01-2006		-added support for track 80-127 (used for loading kickstart)
// 22-01-2006		-removed support for track 80-127 again
// 06-02-2006		-added user disk control input
// 28-12-2006		-spi data out is now low when not addressed to allow multiplexing with multiple spi devices		

module floppy(	clk,reset,enable,horbeam,regaddress,datain,dataout,dmal,dmas,user,
			_step,direc,_sel,side,_motor,_track0,_change,_ready,
			blckint,syncint,wordsync,
			_den,din,dout,dclk);
//bus interface
input 	clk;		    			//bus clock
input 	reset;			   	//reset 
input	enable;				//dma enable
input	[8:0]horbeam;			//horizontal beamcounter
input 	[8:1] regaddress;		//register address inputs
input	[15:0]datain;			//bus data in
output	[15:0]dataout;			//bus data out
output	dmal;				//dma request output
output	dmas;				//dma special output 
//disk control signals from cia and user
input	[2:0]user;			//user disk control
input	_step;				//step heads of disk
input	direc;				//step heads direction
input	_sel;				//disk select 	
input	side;				//upper/lower disk head
input	_motor;				//disk motor control
output	_track0;				//track zero detect
output	_change;				//disk has been removed from drive
output	_ready;				//disk is ready
//interrupt request and misc. control
output	blckint;				//disk dma has finished interrupt
output	syncint;				//disk syncword found
input	wordsync;				//wordsync enable
//flash drive host controller interface	(SPI)
input	_den;				//async. serial data enable
input	din;					//async. serial data input
output	dout;				//async. serial data output
input	dclk;				//async. serial data clock

//register names and addresses
parameter DSKBYTR=9'h01a;
parameter	DSKDAT=9'h026;		
parameter	DSKDATR=9'h008;
parameter DSKSYNC=9'h07e;
parameter	DSKLEN=9'h024;

//local signals
reg		dmal;				//see above
reg		dmas;				//see above
reg		blckint;				//see above
reg		[15:0]dsksync;			//disk sync register
reg		[15:0]dsklen;			//disk dma length, direction and enable 
reg		[7:0]track;			//track select

reg		[15:0]sdshift;			//serial data shift register
reg		[4:0]sdcnt;			//serial data bit counter

reg		[1:0]ldclk;			//serial clock input synchronize register
wire		sdclkpos;				//synchronized serial clock positive edge strobe
wire		sdclkneg;				//synchronized serial clock negative edge strobe
reg		sdin;	 			//synchronized serial data in
reg		_sden;				//synchronized serial enable

reg		dmaon;				//disk dma read/write enabled
wire		lenzero;				//disk length counter is zero
wire		spidat;				//data word read/written by external host
reg		trackwr;				//write track (command to host)
reg		trackrd;				//read track (command to host)
reg		trackch;				//check track (command to host)

reg		_dskchange;			//disk has been removed
reg		_dskready;			//disk is ready (motor running)
wire		_dsktrack0;			//disk heads are over track 0

wire		[15:0]bufdin;			//fifo data in
wire		[15:0]bufdout; 		//fifo data out
wire		bufwr;				//fifo write enable
wire		bufrd;				//fifo read enable
wire		bufempty;				//fifo is empty
wire		buffull;				//fifo is full

wire		[15:0]dskbytr;			
wire		[15:0]dskdatr;

//--------------------------------------------------------------------------------------
//data out multiplexer
assign dataout=dskbytr|dskdatr;

//--------------------------------------------------------------------------------------
//floppy control signal behaviour
reg		_stepd; 		//used to detect rising edge of _step
reg		_seld; 		//used to detect falling edge of _sel
wire		_dsktrack79;	//last track

//_ready,_track0 and _change signals
assign {_track0,_change,_ready}=(!_sel)?{_dsktrack0,_dskchange,_dskready}:3'b111; 

//delay _step and _sel
always @(posedge clk)
begin
	_stepd<=_step;
	_seld<=_sel;
end

//track control
always @(posedge clk)
	track[0]<=~side;
always @(posedge clk)
	if(reset)//reset
		track[7:1]<=0;
	else if((!_dsktrack79 && !direc) || (!_dsktrack0 && direc))//do not step beyond track limits
		track[7:1]<=track[7:1];
	else if(!_sel && _step && !_stepd)//track increment (direc=0) or decrement (direc=1) at rising edge of _step
		track[7:1]<=track[7:1]+{direc,direc,direc,direc,direc,direc,1'b1};

//_dsktrack0 and dsktrack79 detect
assign _dsktrack0=(track[7:1]==7'b0000000)?0:1;
assign _dsktrack79=(track[7:1]==7'b1001111)?0:1;

//motor (ready) control
always @(posedge clk)
	if(reset)//reset
		_dskready<=1;
	else if(!_sel && _seld)//latch _motor signal at falling edge of _sel
		_dskready<=_motor;

//--------------------------------------------------------------------------------------
//async. input synchronizers
always @(posedge clk)
begin
	_sden<=_den;
	sdin<=din;
	ldclk[0]<=dclk;
	ldclk[1]<=ldclk[0];
end

//synchronized clock positive edge detect
assign sdclkpos=ldclk[0]&(~ldclk[1]);

//synchronized clock negative edge detect
assign sdclkneg=(~ldclk[0])&ldclk[1];

//--------------------------------------------------------------------------------------

//disk data byte and status read
assign dskbytr=(regaddress[8:1]==DSKBYTR[8:1])?{1'b0,(trackrd|trackwr),dsklen[14],13'b000000000000}:16'h0000;
	 
//disk sync register
always @(posedge clk)
	if(reset)
		dsksync[15:0]<=0;
	else if(regaddress[8:1]==DSKSYNC[8:1])
		dsksync[15:0]<=datain[15:0];

//disk length dma enable bit
always @(posedge clk)
	if(reset)
		dsklen[15]<=0;
	else if(regaddress[8:1]==DSKLEN[8:1])
		dsklen[15]<=datain[15];

//disk length register
always @(posedge clk)
	if(reset)
		dsklen[14:0]<=0;
	else if(regaddress[8:1]==DSKLEN[8:1] && datain[15] && dsklen[15])//write from bus if second write with dma enabled
		dsklen[14:0]<=datain[14:0];
	else if(bufwr)//decrement length register
		dsklen[13:0]<=dsklen[13:0]-1;

//dsklen zero detect
assign lenzero=(dsklen[13:0]==0)?1:0;

//--------------------------------------------------------------------------------------
//SPI bus
wire		sddone;				//one word has been send/received over the SPI bus
wire		[15:0]sdnew;			//new spi data to send out, loaded when sddone=1
reg		sdl;					//bit to detect if host is reading command or doing data operation
reg		doutl;				//dout output latch

//dout control
assign dout=(!_sden)?doutl:1'b0;

//serial-parallel / parallel-serial converter
always @(posedge clk)
begin
	if(sdclkneg)//data out
		doutl<=sdshift[15];
	if(_sden || sddone)//load now data to send out
		sdshift[15:0]<=sdnew[15:0];
	else if(sdclkpos)//data in
		sdshift[15:0]<={sdshift[14:0],sdin};
end

//bit counter
always @(posedge clk)
	if(_sden || sddone)
		sdcnt[4:0]<=0;
	else if(sdclkpos)
		sdcnt[4:0]<=sdcnt[4:0]+1;
assign sddone=sdcnt[4];

//command multiplexer
assign sdnew[15:0]=(_sden)?{user[2:0],2'b00,trackch,trackrd,trackwr,track[7:0]}:bufdout[15:0];

//sdl bit, this bit is zero if the next completed spi transfer is a command read operation
//this bit is true if the next completed spi transfer is a data operation (read or write)
always @(posedge clk)
	if(_sden)
		sdl=0;
	else if(sddone)
		sdl=1;

//spidat strobe		
assign spidat=sddone&sdl;

//--------------------------------------------------------------------------------------
//disk data read path
wire		busrd;				//bus read
wire		buswr;				//bus write
reg		trackrdok;			//track read enable

//disk buffer bus read address decode
assign busrd=(regaddress[8:1]==DSKDATR[8:1])?1:0;

//disk buffer bus write address decode
assign buswr=(regaddress[8:1]==DSKDAT[8:1])?1:0;

//fifo data input multiplexer
assign bufdin[15:0]=(trackrd)?sdshift[15:0]:datain[15:0];

//fifo write control
assign bufwr=(buswr&dmaon)|(trackrdok&spidat);

//fifo read control
assign bufrd=(busrd&dmaon)|(trackwr&spidat);

//DSKSYNC interrupt
assign syncint=( (dsksync[15:0]==sdshift[15:0]) && spidat && trackrd )?1:0;

//track read enable / wait for syncword logic
always @(posedge clk)
	if(!trackrd)//reset
		trackrdok<=0;
	else//wordsync is enabled, wait with reading untill syncword is found
		trackrdok<=~wordsync|syncint|trackrdok;
		
//disk fifo / trackbuffer
fifo	db1 (	.clk(clk),
			.reset(reset),
			.din(bufdin),
			.dout(bufdout),
			.rd(bufrd),
			.wr(bufwr),
			.full(buffull),
			.empty(bufempty)	);


//disk data read output gate
assign dskdatr[15:0]=(busrd)?bufdout[15:0]:16'h0000;

//--------------------------------------------------------------------------------------
//dma request logic
always @(dmaon or dsklen or bufempty or buffull or horbeam)
	if(dmaon && (horbeam[8:4]==5'b00000) && (horbeam[1:0]==2'b11))//valid memory cycle and dma enabled
	begin
		if(!dsklen[14] && !bufempty)//dma write cycle (disk->ram)
		begin
			dmal=1;
			dmas=0;
		end
		else if(dsklen[14] && !buffull)//dma read cycle	(ram->disk)
		begin
			dmal=1;
			dmas=1;
		end
		else
		begin
			dmal=0;//no track read or write action
			dmas=0;
		end
	end
	else
	begin
		dmal=0;//no valid memory cycle
		dmas=0;
	end

//--------------------------------------------------------------------------------------
//main disk controller
reg		[1:0]dskstate;			//current state of disk
reg		[1:0]nextstate; 		//next state of state

//disk states
parameter	DISKCHANGE=2'b00;
parameter	DISKPRESENT=2'b01;
parameter	DISKDMA=2'b10;
parameter DISKINT=2'b11;

//main disk state machine
always @(posedge clk)
	if(reset)
		dskstate<=DISKCHANGE;		
	else
		dskstate<=nextstate;
always @(dskstate or spidat or sdshift or lenzero or enable or dsklen or bufempty or _sden)
begin
	case(dskstate)
		DISKCHANGE://disk is removed from flash drive, poll drive for new disk
		begin
			trackrd=0;
			trackwr=0;
			trackch=1;
			dmaon=0;
			blckint=0;
			_dskchange=0;
			if(spidat && sdshift[0])//drive response: disk is present
				nextstate=DISKPRESENT;
			else
				nextstate=DISKCHANGE;			
		end
		DISKPRESENT://disk is present in flash drive
		begin
			trackrd=0;
			trackwr=0;
			trackch=1;
			dmaon=0;
			blckint=0;
			_dskchange=1;
			if(spidat && !lenzero && enable)//dsklen>0 and dma enabled, do disk dma operation
				nextstate=DISKDMA; 
			else if(spidat && !sdshift[0])//drive response: disk has been removed
				nextstate=DISKCHANGE;
			else
				nextstate=DISKPRESENT;			
		end
		DISKDMA://do disk dma operation
		begin
			trackrd=(~lenzero)&(~dsklen[14]);//track read (disk->ram)
			trackwr=dsklen[14];//track write (ram->disk)
			trackch=0;
			dmaon=(~lenzero)|(~dsklen[14]);
			blckint=0;
			_dskchange=1;
			if(lenzero && bufempty && _sden)//complete dma cycle done
				nextstate=DISKINT;
			else
				nextstate=DISKDMA;			
		end
		DISKINT://generate disk dma completed (DSKBLK) interrupt
		begin
			trackrd=0;
			trackwr=0;
			trackch=0;
			dmaon=0;
			blckint=1;
			_dskchange=1;
			nextstate=DISKPRESENT;			
		end
		default://we should never come here
		begin
			trackrd=1'bx;
			trackwr=1'bx;
			trackch=1'bx;
			dmaon=1'bx;
			blckint=1'bx;
			_dskchange=1'bx;
			nextstate=DISKCHANGE;			
		end
	endcase

		
end



//--------------------------------------------------------------------------------------

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//8192 words deep, 16 bits wide, fifo
//data is written into the fifo when wr=1
//reading is more or less asynchronous if you read during the rising edge of clk
//because the output data is updated at the falling edge of the clk
//when rd=1, the next data word is selected 
module fifo(clk,reset,din,dout,rd,wr,full,empty);
input 	clk;		    			//bus clock
input 	reset;			   	//reset 
input	[15:0]din;			//data in
output	[15:0]dout;			//data out
input	rd;					//read from fifo
input	wr;					//write to fifo
output	full;				//fifo is full
output	empty;				//fifo is empty

//local signals and registers
reg		empty;				//see above, delayed one clock to handle sync. ram delay
reg		[15:0]dout;			//see above
reg 		[15:0]mem[8191:0];		//8192 words by 16 bit wide fifo memory
reg		[13:0]inptr;			//fifo input pointer
reg		[13:0]outptr;			//fifo output pointer
wire		equal;				//lower 13 bits of inptr and outptr are equal

//main fifo memory (implemented using synchronous block ram)
always @(posedge clk)
	if (wr && !full)
		mem[inptr[12:0]]<=din;
always @(posedge clk)
	dout=mem[outptr[12:0]];

//fifo write pointer control
always @(posedge clk)
	if(reset)
		inptr[13:0]<=0;
	else if(wr && !full)
		inptr[13:0]<=inptr[13:0]+1;

//fifo read pointer control
always @(posedge clk)
	if(reset)
		outptr[13:0]<=0;
	else if(rd && !empty)
		outptr[13:0]<=outptr[13:0]+1;

//check lower 13 bits of pointer to generate equal signal
assign equal=(inptr[12:0]==outptr[12:0])?1:0;

//assign output flags, empty is delayed by one clock to handle ram delay
always @(posedge clk)
	if(equal && (inptr[13]==outptr[13]))
		empty=1;
	else
		empty=0;	
assign full=(equal && (inptr[13]!=outptr[13]))?1:0;	

endmodule