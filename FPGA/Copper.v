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
// This is the Copper (part of the Agnus chip)
//
// 24-05-2005		-started coding (created all user accessible registers)
// 25-05-2005		-added beam counter compare logic
// 29-05-2005		-added blitter finished disable logic
//				-added copper danger/address range check logic
//				-added controlling state machine
//				-adapted to use reqdma/ackdma model
//				-first finished version
// 11-09-2005		-added proper reset for copper location registers
// 24-09-2005		-fixed bug, when an illegal register is loaded by MOVE,
//				 the copper must halt until the next strobe or vertical blank.
//				 the copper now does this properly
// 02-10-2005		-modified skip instruction to only skip MOVE instructions.
// 19-10-2005		-replaced vertb (vertical blank) signal by sof (start of frame)
// 07-12-2005		-added dummy cycle after copper wakeup, this is needed for copperlists
//				 that wait for vertical beamcounter rollover ($FFDF,FFFE)
//				 The dummy cycle is indicated by making both selins and selreg high.
// 26-12-2005		-added exception for last cycle of horizontal line, this cycle is not used by copper

module copper(clk,reset,reqdma,ackdma,sof,bbusy,horbeam,verbeam,datain,regaddressin,regaddressout,addressout);
input 	clk;	 				//bus clock
input 	reset;	 			//reset
output	reqdma;				//copper requests dma cycle
input	ackdma;				//agnus dma priority logic grants dma cycle
input	sof;					//start of frame input
input	bbusy;				//blitter busy flag input
input	[8:0]horbeam;		    	//horizontal beam counter
input	[7:0]verbeam;			//vertical beam counter
input 	[15:0] datain;	    		//bus data in
input 	[8:1] regaddressin;		//register address inputs
output 	[8:1] regaddressout; 	//register address outputs
output 	[20:1] addressout; 		//chip address outputs


//register names and adresses		
parameter COP1LCH=9'h080;
parameter COP1LCL=9'h082;
parameter COP2LCH=9'h084;
parameter COP2LCL=9'h086;
parameter	COPCON=9'h02e;
parameter COPINS=9'h08c;
parameter COPJMP1=9'h088;
parameter COPJMP2=9'h08a;
			

//local signals
reg		[8:1]regaddressout;		//see above
reg		reqdma;				//see above
reg		[20:16]cop1lch;		//copper location register 1
reg		[15:1]cop1lcl;			//copper location register 1
reg		[20:16]cop2lch;		//copper location register 2
reg		[15:1]cop2lcl;			//copper location register 2
reg		cdang;				//copper danger bit
reg		[15:1]ir1;			//instruction register 1
reg		[15:0]ir2;			//instruction register 2
reg		[20:1]addressout;		//copper address out (coppper program counter)
reg		[1:0]copperstate;		//current state of copper state machine
reg		[1:0]coppernext;		//next state of copper state machine

reg		strobe1;				//strobe 1 
reg		strobe2;				//strobe 2 
reg		beammatch;			//true if beamcounters >= value in instruction register
reg		illegalreg;			//illegal register (MOVE instruction)
reg		skipmove;				//skip move instruction latch
reg		selins;				//load instruction register (register address out = COPINS)
reg		selreg;				//load chip register address, when both selins and selreg are active
							//a dummy cycle is executed
reg		skip;				//skip next move instruction

//--------------------------------------------------------------------------------------

//write copper location register 1 high and low word
always @(posedge clk)
	if(reset)
		cop1lch[20:16]<=0;
	else if(regaddressin[8:1]==COP1LCH[8:1])
		cop1lch[20:16]<=datain[4:0];
always @(posedge clk)
	if(reset)
		cop1lcl[15:1]<=0;
	else if(regaddressin[8:1]==COP1LCL[8:1])
		cop1lcl[15:1]<=datain[15:1];

//write copper location register 2 high and low word
always @(posedge clk)
	if(reset)
		cop2lch[20:16]<=0;
	else if(regaddressin[8:1]==COP2LCH[8:1])
		cop2lch[20:16]<=datain[4:0];
always @(posedge clk)
	if(reset)
		cop2lcl[15:1]<=0;
	else if(regaddressin[8:1]==COP2LCL[8:1])
		cop2lcl[15:1]<=datain[15:1];

//write copcon register (copper danger bit)
always @(posedge clk)
	if(reset)
		cdang<=0;
	else if(regaddressin[8:1]==COPCON[8:1])
		cdang<=datain[1];

//copper instruction registers ir1 and ir2
always @(posedge clk)
	if(regaddressin[8:1]==COPINS[8:1])
	begin
		ir1[15:1]<=ir2[15:1];
		ir2[15:0]<=datain[15:0];
	end

//--------------------------------------------------------------------------------------

//chip address pointer (or copper program counter) controller
always @(posedge clk)
	if(strobe1)//load pointer with location register 1
		addressout[20:1]<={cop1lch[20:16],cop1lcl[15:1]};
	else if(strobe2)//load pointer with location register 2
		addressout[20:1]<={cop2lch[20:16],cop2lcl[15:1]};
	else if(ackdma && !(selins&selreg))//increment address pointer (when not dummy cycle) 
		addressout[20:1]<=addressout[20:1]+1;

//--------------------------------------------------------------------------------------

//regaddress output select
//if selins=1 the address of the copper instruction register
//is sent out (not strictly necessary as we can load copins directly. However, this is 
//more according to what happens in a real amiga... I think), else the contents of
//ir2[8:1] is selected 
//(if you ask yourself: IR2? is this a bug? then check how ir1/ir2 are loaded in this design)
always @(selins or ir2)
	if(selins)//load our own instruction register(selins has priority to safely handle dummy cycle)
		regaddressout[8:1]=COPINS[8:1];
	else//load other register
		regaddressout[8:1]=ir2[8:1];

//detect illegal register access
always @(ir2 or cdang)
	if(ir2[8:6]==3'b000)//$000 -> $03E always illegal
		illegalreg=1;
	else if((ir2[8:6]==3'b001) && (cdang==0))//$040 -> $07E illegal if cdang=0
		illegalreg=1;
	else//$080 -> $1FE always allowed
		illegalreg=0;

//skipmove latch
always @(posedge clk)
	if(ackdma)
		skipmove<=skip;

//--------------------------------------------------------------------------------------

//strobe1 (also triggered by sof, start of frame)
always @(regaddressin or sof)
	if( (regaddressin[8:1]==COPJMP1[8:1]) || sof )
		strobe1=1;
	else
		strobe1=0;

//strobe2
always @(regaddressin)
	if(regaddressin[8:1]==COPJMP2[8:1])
		strobe2=1;
	else
		strobe2=0;

//--------------------------------------------------------------------------------------

//beam compare circuitry
//when the mask for a compare bit is 1, the beamcounter is compared with that bit,
//when the mask is 0, the compare bit is replaced with the corresponding beamcounter bit
//itself, thus the compare is always true.
//the blitter busy flag is also checked if blitter finished disable is false

wire [8:2]horcmp;
wire [7:0]vercmp;

//construct compare value for horizontal beam counter (4 lores pixels resolution)
assign horcmp[2]=(ir2[1])?ir1[1]:horbeam[2];
assign horcmp[3]=(ir2[2])?ir1[2]:horbeam[3];
assign horcmp[4]=(ir2[3])?ir1[3]:horbeam[4];
assign horcmp[5]=(ir2[4])?ir1[4]:horbeam[5];
assign horcmp[6]=(ir2[5])?ir1[5]:horbeam[6];
assign horcmp[7]=(ir2[6])?ir1[6]:horbeam[7];
assign horcmp[8]=(ir2[7])?ir1[7]:horbeam[8];

//construct compare value for vertical beam counter (1 line resolution)
assign vercmp[0]=(ir2[8])?ir1[8]:verbeam[0];
assign vercmp[1]=(ir2[9])?ir1[9]:verbeam[1];
assign vercmp[2]=(ir2[10])?ir1[10]:verbeam[2];
assign vercmp[3]=(ir2[11])?ir1[11]:verbeam[3];
assign vercmp[4]=(ir2[12])?ir1[12]:verbeam[4];
assign vercmp[5]=(ir2[13])?ir1[13]:verbeam[5];
assign vercmp[6]=(ir2[14])?ir1[14]:verbeam[6];
assign vercmp[7]=ir1[15];
 
//final beamcounter compare logic 
//(also takes bbusy/blitter finished disable into account)
always @(horbeam or verbeam or vercmp or horcmp or ir2[15] or bbusy)
	if({verbeam[7:0],horbeam[8:2]}>={vercmp[7:0],horcmp[8:2]})
	begin
		if(ir2[15])//blitter finished disabled
			beammatch=1;
		else if(!bbusy)//blitter is finished
			beammatch=1;
		else//blitter not finished yet
			beammatch=0;
	end
	else
		beammatch=0;

//--------------------------------------------------------------------------------------
    
//copper states
parameter	FETCH1=2'b00;
parameter	FETCH2=2'b01;
parameter WAITSKIP=2'b10;

//copper state machine
always @(posedge clk)
	if(reset || strobe1 || strobe2)//on strobe or reset fetch first instruction word
		copperstate<=FETCH1;
	else if(ackdma)//if granted dma cycle go to next state
		copperstate<=coppernext;

always @(copperstate or ir2 or beammatch or illegalreg or skipmove)
begin
	case(copperstate)
		//fetch first instruction word
		FETCH1:
		begin
			skip=0;
			selins=1;
			selreg=0;
			coppernext=FETCH2;
		end

		//fetch second instruction word, skip or do MOVE instruction or halt copper
		FETCH2:			
		begin
			if(!ir2[0] && illegalreg)//illegal MOVE instruction, halt copper
			begin
				skip=0;
				selins=0;
				selreg=0;
				coppernext=FETCH2;
			end
			else if(!ir2[0] && skipmove)//skip this MOVE instruction
			begin
				skip=0;
				selins=1;
				selreg=0;
				coppernext=FETCH1;
			end
			else	if(!ir2[0])//MOVE instruction
			begin
				skip=0;
				selins=0;
				selreg=1;
				coppernext=FETCH1;
			end
			else//fetch second instruction word of WAIT or SKIP instruction
			begin
				skip=0;
				selins=1;
				selreg=0;
				coppernext=WAITSKIP;
			end
		end

		//WAIT or SKIP instruction
		WAITSKIP:
		begin
			if(!ir2[0])//WAIT instruction
			begin
				if(beammatch)//wait is over, fetch next instruction
				begin
					skip=0;
					selins=1;//both selins and selreg high --> this is a dummy cycle
					selreg=1;//both selins and selreg high --> this is a dummy cycle
					coppernext=FETCH1;
				end
				else//still waiting
				begin
					skip=0;
					selins=0;
					selreg=0;
					coppernext=WAITSKIP;
				end
			end
			else//SKIP instruction
			begin
				if(beammatch)//compare is true, skip next move, fetch next instruction
				begin
					skip=1;
					selins=1;
					selreg=0;
					coppernext=FETCH2;
				end
				else//do not skip, fetch next instruction
				begin
					skip=0;
					selins=1;
					selreg=0;
					coppernext=FETCH2;
				end
			end
		end

		//default, go back to reset state
		default:
		begin
			skip=1'bx;
			selins=1'bx;
			selreg=1'bx;
			coppernext=FETCH1;
		end
		
	endcase
end	

//--------------------------------------------------------------------------------------

//generate request dma (reqdma) signal			 
//for a dma to be requested first of all the cycle must be right (horbeam[1:0])
//second, selins or selreg must be true (state machine request bus operation)
//the last cycle in a line is not usable by the copper
always @(selins or selreg or horbeam[1:0])
	if( (horbeam[8:2]!=7'b1110001) && (horbeam[1:0]==2'b01) && (selins || selreg) )//request dma cycle
		reqdma=1;		
	else
		reqdma=0;

//--------------------------------------------------------------------------------------

endmodule
