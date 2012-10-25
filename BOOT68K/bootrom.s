* Copyright 2006, 2007, 2008 Dennis van Weeren
*
* This file is part of Minimig
*
* Minimig is free software; you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation; either version 3 of the License, or
* (at your option) any later version.
*
* Minimig is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*
*
* 20-01-2008	-added support for keyfile encrypted roms
* 22-01-2008	-added simple RAM test
* 27-01-2008	-RAM test speedup
* 26-03-2008	-started redesign for better encrypted rom handling
* 13-04-2008	-added WORKING support for 256Kb and 512Kb encryped roms


*Some amiga register definitions
SERDATR	equ	$018
SERPER	equ	$032
SERDAT	equ	$030
INTREQ	equ	$09c
INTREQR	equ	$01e
CUSTOM	equ	$dff000
INTENA	equ	$09a
INTENAR	equ	$01c
CIAA	equ	$bfe001
CIAB	equ	$bfd000

CIAPRA	equ	$000	
CIAPRB	equ	$100
CIADDRA	equ	$200
CIADDRB	equ	$300	
CIATALO	equ	$400
CIATAHI	equ	$500
CIATBLO	equ	$600
CIATBHI	equ	$700
CIATODLOW equ	$800
CIATODMID equ	$900
CIATODHI equ	$a00
CIASDR	equ	$c00
CIAICR	equ	$d00
CIACRA	equ	$e00
CIACRB	equ	$f00

VPOSR	equ	$004
DDFSTRT	equ	$092
DDFSTOP	equ	$094
DIWSTRT	equ	$08e
DIWSTOP	equ	$090
BPL1MOD	equ	$108
BPL2MOD	equ	$10a

COP1LCH	equ	$080
COP2LCH	equ	$084
COPJMP1 equ	$088
COPJMP2	equ	$08a


BPL1DAT	equ	$110
BPL1PTH	equ	$0e0
BPL1PTL	equ	$0e2
BPL2PTH	equ	$0e4
BPL2PTL	equ	$0e6
BPL3PTH	equ	$0e8
BPL3PTL	equ	$0ea
BPL4PTH	equ	$0ec
BPL4PTL	equ	$0ee
BPLCON0	equ	$100
BPLCON1	equ	$102
BPLCON2	equ	$104
COLOR00	equ	$180
COLOR01	equ	$182
COLOR02	equ	$184
COLOR03	equ	$186
COLOR09 equ	$192
COLOR10 equ	$194
COLOR11 equ	$196

DMACON	equ	$096
DMACONR	equ	$002

BLTAFWM	equ	$044
BLTALWM	equ	$046
BLTCON0	equ	$040
BLTCON1	equ	$042
BLTSIZE	equ	$058

BLTAMOD	equ	$064
BLTBMOD	equ	$062
BLTCMOD	equ	$060
BLTDMOD	equ	$066

BLTADAT	equ	$074
BLTBDAT	equ	$072
BLTCDAT	equ	$070

BLTAPTH	equ	$050
BLTBPTH	equ	$04c
BLTCPTH	equ	$048
BLTDPTH	equ	$054

DSKLEN	equ	$024
DSKPTH	equ	$020
DSKSYNC	equ	$07e
ADKCON	equ	$09e


* Code starts here

	org	$0

	dc.W	$000f,$8000		;initial stack pointer
	dc.W	$0000,$0100		;reset pointer

	org	$100

Start:	lea	CUSTOM,a0		;pointer to chip registers
	lea	CIAA,a1			;pointer to ciaa
	lea	CIAB,a2			;pointer to ciab

	move.b	#$f7,CIAPRB(a2)		;select drive 0
	move.b	#$ff,CIADDRB(a2)	;make drive control signals output
	move.b	#$02,CIADDRA(a1)	;make led output
	move.W	#30,SERPER(a0)		;set baud to 115200 @ 3.547 MHz
	move.W	#$7000,INTENA(a0)	;disable all intterupts
	move.w	#$7fff,INTREQ(a0)	;clear all intterupts
	move.w	#$8210,DMACON(a0)	;enable only disk dma
	move.w	#$7fff,ADKCON(a0)	;clear ADKCON
	bset.b	#0,CIAPRA(a1)		;led indicates core is up

	bsr	Tst			;do RAM test

TstRet	bsr	Trck0			;go to track 0
	bclr	#1,CIAPRB(a2)		;step upwards

	lea	$010000,a4		;pointer to buffer
	bsr	Rd16k			;read first 16k bytes of rom image into buffer
	cmpi.l	#$414d4952,$010000	;check if this is an encrypted rom
	bne	RomSkp

	bsr	AfRom			;Amiga forever 256K or 512K encrypted rom
	bra	Exit

RomSkp	bsr	StdRom			;512K non-encrypted rom
	bra	Exit

	
***************************************************************************
*Do RAM test...
***************************************************************************
Tst	move.l	#$aaaaaaaa,d0		;test pattern 1
	move.l	#$55555555,d1		;test pattern 2

*test bank#0 / IC7
	lea	$100000,a3		;pointer to mirror bank of chipram
	move.w	#$00f0,COLOR00(a0)	;background to green
TstLP1	move.l	d0,(a3)			;test with pattern 1
	cmp.l	(A3),d0
	bne	TstErr
	move.l	d1,(a3)			;test with pattern 2
	cmp.l	(A3)+,d1
	bne	TstErr
	move.l	d0,(a3)			;test with pattern 1
	cmp.l	(A3),d0
	bne	TstErr
	move.l	d1,(a3)			;test with pattern 2
	cmp.l	(A3)+,d1
	bne	TstErr
	cmp.l	#$200000,a3		;all addresses done ?
	bne	TstLP1

*test first half bank#1 / IC6
	lea	$c00000,a3		;pointer to ranger memory
	move.w	#$0f00,COLOR00(a0)	;background to red
TstLP2	move.l	d0,(a3)			;test with pattern 1
	cmp.l	(A3),d0
	bne	TstErr
	move.l	d1,(a3)			;test with pattern 2
	cmp.l	(A3)+,d1
	bne	TstErr
	move.l	d0,(a3)			;test with pattern 1
	cmp.l	(A3),d0
	bne	TstErr
	move.l	d1,(a3)			;test with pattern 2
	cmp.l	(A3)+,d1
	bne	TstErr
	cmp.l	#$c80000,a3		;all addresses done ?
	bne	TstLP2

*test second half bank#1 / IC6
	lea	$f80000,a3		;pointer to kickstart area
	move.w	#$000f,COLOR00(a0)	;background to blue
TstLP3	move.l	d0,(a3)			;test with pattern 1
	cmp.l	(A3),d0
	bne	TstErr
	move.l	d1,(a3)			;test with pattern 2
	cmp.l	(A3)+,d1
	bne	TstErr
	move.l	d0,(a3)			;test with pattern 1
	cmp.l	(A3),d0
	bne	TstErr
	move.l	d1,(a3)			;test with pattern 2
	cmp.l	(A3)+,d1
	bne	TstErr
	cmp.l	#$1000000,a3		;all addresses done ?
	bne	TstLP3

	bra	TstRet			;return from this test


TstErr	bra	TstErr

***************************************************************************
*load 512k non-encrypted rom from disk
***************************************************************************
StdRom	lea	$f80000,a3		;pointer to kickstart area
	lea	$010000,a4		;pointer to buffer
	bsr	Cpy16k			;copy buffer to kickstart area
	
StdRomL	lea	$010000,a4		;pointer to buffer
	bsr	Rd16k			;read track into buffer
	lea	$010000,a4		;pointer to buffer
	bsr	Cpy16k			;copy buffer to kickstart area
	cmp.l	#$1000000,a3		;all data done ?
	beq	StdRomX			;yes --> exit 
	bclr	#0,CIAPRB(a2)		;no  --> load next track
	bset	#0,CIAPRB(a2)
	bra	StdRomL	
StdRomX	rts

***************************************************************************
*load 256k or 512k Amiga Forever encrypted rom from disk
***************************************************************************
AfRom	lea	$014000,a4		;pointer to buffer
AfromL1	bsr	Rd16k			;read 16384 bytes
	add.l	#$4000,a4		;update pointer to buffer
	cmp.l	#$050000,a4		;done ?
	bne	AfromL1			;no --> loop 
	bsr	Rd2k			;read 2082 bytes
	add.l	#$822,a4		;update pointer to buffer	

*now check if we are still getting data,
*if we do, rom is 512kb and we need to load more data.
*Else rom is 256kb and we can start decoding

	bsr	W500			;wait 500ms for host to	update dskchange	
	btst.b	#2,CIAPRA(a1)		;check dskchange 
	beq	AfRom2			;low  --> decode 256K rom
	
AfromL2	bsr	Rd16k			;read 16384 bytes
	add.l	#$4000,a4		;update pointer to buffer
	cmp.l	#$090822,a4		;done ?
	bne	AfromL2			;no --> loop 
	bra	AfRom5			;decode 512K rom

AfRom2
*copy rom to kickstart area....
	lea	$f80000,a3
	lea	$01000b,a4
	move.l	#262144,d0		;size of rom
	bsr	CpyX

*apply keyfile...
	lea	$f80000,a4		;pointer to rom
	lea	$05000c,a3		;pointer to key
	move.w	#2069,d1		;length of key
	move.l	#262144,d0		;size of rom
	bsr	DoKey

*and copy mirror of rom
	lea	$fc0000,a3		
	lea	$f80000,a4
	move.l	#262144,d0		;size of rom
	bsr	CpyX

	rts				;exit

AfRom5	
*copy rom to kickstart area....
	lea	$f80000,a3
	lea	$01000b,a4
	move.l	#524288,d0		;size of rom
	bsr	CpyX

*apply keyfile...
	lea	$f80000,a4		;pointer to rom
	lea	$09000c,a3		;pointer to key
	move.w	#2069,d1		;length of key
	move.l	#524288,d0		;size of rom
	bsr	DoKey

	rts				;exit

***************************************************************************
* Wait for 50ms
***************************************************************************
W50	move.b	#$00,CIACRA(a1)		;normal mode
	move.b	#$8d,CIATALO(a1)	;set timer interval to 50ms
	move.b	#$80,CIATAHI(a1)
	move.b	#%01111111,CIAICR(a1)	;clear all 8520 interrupts
	move.b	#$08,CIACRA(a1)		;enable one-shot mode
	bset.b	#0,CIACRA(a1)		;start timer

W50LP	btst.b	#0,CIAICR(a1)		;wait for timer to expire
	beq	W50LP
	rts

***************************************************************************
* Wait for 500ms 
***************************************************************************
W500	bsr	W50
	bsr	W50
	bsr	W50
	bsr	W50
	bsr	W50
	bsr	W50
	bsr	W50
	bsr	W50
	bsr	W50
	bsr	W50
	rts

***************************************************************************
* go to track0
***************************************************************************
Trck0	move.b	#255,d0			;256 _step pulses
	bset	#1,CIAPRB(a2)		;step towards track 0
	
Trck0L	bclr	#0,CIAPRB(a2)		;pulse _step
	bset	#0,CIAPRB(a2)
	dbra	d0,Trck0L
	rts

***************************************************************************
*read 2082 bytes from disk into the chipram buffer
***************************************************************************
Rd2k	move.l	a4,DSKPTH(a0)		;pointer to chipram buffer
	move.w	#$0002,INTREQ(a0)	;clear interrupt
	move.w	#$8411,DSKLEN(a0)	;start disk dma
	move.w	#$8411,DSKLEN(a0)
Rd2kL	move.w	INTREQR(a0),d0		;wait for disk dma to finish
	and.w	#$0002,d0
	beq	Rd2kL
	move.w	#$4000,DSKLEN(a0)	;stop disk dma
	rts

***************************************************************************
*read 16kbyte (16384 bytes) from disk into the chipram buffer
***************************************************************************
Rd16k	move.l	a4,DSKPTH(a0)		;pointer to chipram buffer
	move.w	#$0002,INTREQ(a0)	;clear interrupt
	move.w	#$a000,DSKLEN(a0)	;start disk dma
	move.w	#$a000,DSKLEN(a0)
Rd16kL	move.w	INTREQR(a0),d0		;wait for disk dma to finish
	and.w	#$0002,d0
	beq	Rd16kL
	move.w	#$4000,DSKLEN(a0)	;stop disk dma
	rts

***************************************************************************
*copy 16kbyte from <a4> to <a3>
***************************************************************************
Cpy16k	move.w	#4095,d0		;4096 words
Cpy16kL	move.l	(a4)+,d1		;copy one word
	move.l	d1,(a3)+		;still copying one word
	move.w	d1,COLOR00(a0)		;funny screen flash
	dbra	d0,Cpy16kL
	rts
			
***************************************************************************
*copy <d0> bytes from <a4> to <a3>
***************************************************************************
CpyX	move.b	(a4)+,d1		;copy one word
	move.b	d1,(a3)+		;still copying one word
	move.w	d1,COLOR00(a0)		;funny screen flash
	sub.l	#1,d0
	bne	CpyX
	rts

***************************************************************************
*apply keyfile
***************************************************************************

DoKey	move.w 	#0,d2			;reset key length counter
	move.l	a3,a5			;reset key pointer

DoKeyL	move.b	(a5)+,d3		;get a byte of the key	
	eor.b	d3,(a4)+		;xor key to rom image
	move.w	d3,COLOR00(a0)		;funny screen flash
	add.w	#1,d2			;increment key length counter
	sub.l	#1,d0			;decrement rom length counter

	cmp.l	#0,d0			;end of rom?
	beq	DoKeyX			;yes, exit

	cmp.w	d1,d2			;end of keyfile?
	beq	DoKey			;yes, reset key counter/pointer

	bra	DoKeyL

DoKeyX	rts



			
***************************************************************************
* exit boot code
***************************************************************************
Exit	move.b	d0,$bfc000		;access both cia's at once, this will end boot code
	bra	Exit

			

	


