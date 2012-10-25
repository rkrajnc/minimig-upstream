/*
Copyright 2005, 2006, 2007, 2008 Dennis van Weeren

This file is part of Minimig

Minimig is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

Minimig is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

This is the lowlevel ATA (actually MMC/SD card) driver

19-04-2005		-start of project
11-12-2005		-(Dennis) added proper CS handling to enable sharing of SPI bus
20-01-2008		-merged improvements made by Jan Derogee back into Minimig firmware
*/

#include <pic18.h>
#include <stdio.h>
#include "ata.h"
#include "hardware.h"

/*IO definitions*/
#define		SDCARD_CS	_M_CS

/*constants*/   
#define		FALSE		0			/*FALSE*/
#define		TRUE		1			/*TRUE*/
#define		MMCCARD		2
#define		SDCARD		3

/*MMC commandset*/
#define		CMD0		0x40		/*Resets the multimedia card*/
#define		CMD1		0x41		/*Activates the card's initialization process*/
#define		CMD2		0x42		/*--*/
#define		CMD3		0x43		/*--*/
#define		CMD4		0x44		/*--*/
#define		CMD5		0x45		/*reseved*/
#define		CMD6		0x46		/*reserved*/
#define		CMD7		0x47		/*--*/
#define		CMD8		0x48		/*reserved*/
#define		CMD9		0x49		/*CSD : Ask the selected card to send its card specific data*/
#define		CMD10		0x4a		/*CID : Ask the selected card to send its card identification*/
#define		CMD11		0x4b		/*--*/
#define		CMD12		0x4c		/*--*/
#define		CMD13		0x4d		/*Ask the selected card to send its status register*/
#define		CMD14		0x4e		/*--*/
#define		CMD15		0x4f		/*--*/
#define		CMD16		0x50		/*Select a block length (in bytes) for all following block commands (Read:between 1-512 and Write:only 512)*/
#define		CMD17		0x51		/*Reads a block of the size selected by the SET_BLOCKLEN command, the start address and block length must be set so that the data transferred will not cross a physical block boundry*/
#define		CMD18		0x52		/*--*/
#define		CMD19		0x53		/*reserved*/
#define		CMD20		0x54		/*--*/
#define		CMD21		0x55		/*reserved*/
#define		CMD22		0x56		/*reserved*/
#define		CMD23		0x57		/*reserved*/
#define		CMD24		0x58		/*Writes a block of the size selected by CMD16, the start address must be alligned on a sector boundry, the block length is always 512 bytes*/
#define		CMD25		0x59		/*--*/
#define		CMD26		0x5a		/*--*/
#define		CMD27		0x5b		/*Programming of the programmable bits of the CSD*/
#define		CMD28		0x5c		/*If the card has write protection features, this command sets the write protection bit of the addressed group. The porperties of the write protection are coded in the card specific data (WP_GRP_SIZE)*/
#define		CMD29		0x5d		/*If the card has write protection features, this command clears the write protection bit of the addressed group*/
#define		CMD30		0x5e		/*If the card has write protection features, this command asks the card to send the status of the write protection bits. 32 write protection bits (representing 32 write protect groups starting at the specific address) followed by 16 CRD bits are transferred in a payload format via the data line*/
#define		CMD31		0x5f		/*reserved*/
#define		CMD32		0x60		/*sets the address of the first sector of the erase group*/
#define		CMD33		0x61		/*Sets the address of the last sector in a cont. range within the selected erase group, or the address of a single sector to be selected for erase*/
#define		CMD34		0x62		/*Removes on previously selected sector from the erase selection*/
#define		CMD35		0x63		/*Sets the address of the first erase group within a range to be selected for erase*/
#define		CMD36		0x64		/*Sets the address of the last erase group within a continuos range to be selected for erase*/
#define		CMD37		0x65		/*Removes one previously selected erase group from the erase selection*/
#define		CMD38		0x66		/*Erases all previously selected sectors*/
#define		CMD39		0x67		/*--*/
#define		CMD40		0x68		/*--*/
#define		CMD41		0x69		/*reserved*/
#define		CMD42		0x6a		/*reserved*/
#define		CMD43		0x6b		/*reserved*/
#define		CMD44		0x6c		/*reserved*/
#define		CMD45		0x6d		/*reserved*/
#define		CMD46		0x6e		/*reserved*/
#define		CMD47		0x6f		/*reserved*/
#define		CMD48		0x70		/*reserved*/
#define		CMD49		0x71		/*reserved*/
#define		CMD50		0x72		/*reserved*/
#define		CMD51		0x73		/*reserved*/
#define		CMD52		0x74		/*reserved*/
#define		CMD53		0x75		/*reserved*/
#define		CMD54		0x76		/*reserved*/
#define		CMD55		0x77		/*reserved*/
#define		CMD56		0x78		/*reserved*/
#define		CMD57		0x79		/*reserved*/
#define		CMD58		0x7a		/*reserved*/
#define		CMD59		0x7b		/*Turns the CRC option ON or OFF. A '1' in the CRC option bit will turn the option ON, a '0' will turn it OFF*/
#define		CMD60		0x7c		/*--*/
#define		CMD61		0x7d		/*--*/
#define		CMD62		0x7e		/*--*/
#define		CMD63		0x7f		/*--*/

/*variables*/
unsigned char crc_7;			/*contains CRC value*/
unsigned int timeout;
unsigned char response_1;		/*byte that holds the first response byte*/
unsigned char response_2;		/*byte that holds the second response byte*/
unsigned char response_3;		/*byte that holds the third response byte*/
unsigned char response_4;		/*byte that holds the fourth response byte*/
unsigned char response_5;		/*byte that holds the fifth response byte*/

/*internal functions*/
Command_R0(char cmd,unsigned short AdrH,unsigned short AdrL);
Command_R1(char cmd,unsigned short AdrH,unsigned short AdrL);
Command_R2(char cmd,unsigned short AdrH,unsigned short AdrL);
Command_R3(char cmd,unsigned short AdrH,unsigned short AdrL);
void MmcAddCrc7(unsigned char c);

//todo:
//-----

void SPI_LowSpeed(void);
void SPI_HighSpeed(void);
unsigned char Card_CMD0(void);
unsigned char Card_CMD1(void);
unsigned char Card_BlockSize(void);
unsigned char WaitForSOD(void);

/*************************************************************************************/
/*************************************************************************************/
/*External functions*/
/*************************************************************************************/
/*************************************************************************************/

void SPI_LowSpeed(void)
{
	/*set SPI speed to lowest possible during init*/
	SSPM3 = 0;		/*Speed f/64(312kHz @ 20MHz crystal), Master*/
	SSPM2 = 0;
	SSPM1 = 1;		
	SSPM0 = 0;
}

void SPI_HighSpeed(void)
{
	/*set SPI speed to higher rate for better performance (max. speed SD=3.125 MBits/sec)*/
	SSPM3 = 0;		/*Speed f/64(1,25MHz @ 20MHz crystal), Master*/
	SSPM2 = 0;
	SSPM1 = 0;		
	SSPM0 = 1;
}

/*wait for start of data transfer with timeout*/
unsigned char WaitForSOD(void)
{
	timeout = 0;
	while(SPI(0xFF) != 0xFE)
		if (timeout++ >= 1000)					
		{
			return(FALSE);
		}
	return(TRUE);
}


/*Enable the MMC/SD-card correctly*/
unsigned char CARD_Init(void)
{
	unsigned short lp;

	SPI_LowSpeed();
	_M_CD=1;									/*enable clock*/
	SDCARD_CS=1;								/*SDcard Disabled*/
	for(lp=0; lp < 10; lp++)					/*Set SDcard in SPI-Mode, Reset*/
		SPI(0xFF);								/*10 * 8bits = 80 clockpulses*/
	SDCARD_CS=0;								/*SDcard Enabled*/

	for(lp=0; lp < 50000; lp++);				/*delay for a lot of milliseconds (at least 16 bus clock cycles)*/

	if (Card_CMD0() == FALSE)
	{
		DisableCard();
		return(FALSE);							/*error, quit routine*/
	}

	Command_R1(CMD55,0,0);						/*when the response is 0x04 (illegal command), this must be an MMC-card*/
	if (response_1 == 0x05)						/*determine MMC or SD*/
	{	/*An MMC-card has been detected, handle accordingly*/
		/*-------------------------------------------------*/
		if (Card_CMD1() == FALSE)
		{
			DisableCard();
			return(FALSE);						/*error, quit routine*/
		}
	}
	else
	{	/*An SD-card has been detected, handle accordingly*/
		/*-------------------------------------------------*/
		timeout = 0;
		response_1 = 1;
		while(response_1 != 0)
		{
			Command_R1(CMD41,0,0);
			Command_R1(CMD55,0,0);
			if (timeout == 10000)				/*timeout mechanism*/
			{
				DisableCard();
				return(FALSE);					/*error, quit routine*/
			}
			timeout++;
		}
	}

	if (Card_BlockSize() == FALSE)
	{
		DisableCard();
		return(FALSE);							/*error, quit routine*/
	}

	SPI_HighSpeed();
	return(TRUE);					
}

/*Enable the SDcard according SanDisk RS-MMC (a.k.a. the idiots not follow the world's standards*/
unsigned char CARD_AlternativeInit(void)
{
	unsigned short 	lp;

	SPI_LowSpeed();
	_M_CD=1;									/*enable clock*/
	SDCARD_CS=1;								/*SDcard Disabled*/
	for(lp=0; lp < 10; lp++)					/*Set SDcard in SPI-Mode, Reset*/
		SPI(0xFF);								/*10 * 8bits = 80 clockpulses*/
	SDCARD_CS=0;								/*SDcard Enabled*/

	for(lp=0; lp < 50000; lp++);				/*delay for a lot of milliseconds (at least 16 bus clock cycles)*/

	if (Card_CMD0() == FALSE)
	{
		DisableCard();
		return(FALSE);							/*error, quit routine*/
	}

	if (Card_CMD1() == FALSE)
	{
		DisableCard();
		return(FALSE);							/*error, quit routine*/
	}

	if (Card_BlockSize() == FALSE)
	{
		DisableCard();
		return(FALSE);							/*error, quit routine*/
	}

	SPI_HighSpeed();
	return(TRUE);					
}


unsigned char Card_BlockSize(void)
{
	unsigned char	retry_counter;

	retry_counter = 100;						/*this routine is verrrrrrrry important, and sometimes fails on some cards so a retry mechanism is crucial*/
	while(retry_counter--)
	{
		Command_R1(CMD16,0,512);				/*Set read block length to 512 bytes, by the way 512 is default, but since nobody if following standards...*/
		if (response_1 == 0)
			break;

		if (retry_counter == 0)
			return(FALSE);
	}
	return(TRUE);
}



/*Read single block (with block-size set by CMD16 to 512 by default)*/
unsigned char AtaReadSector(unsigned long lba, unsigned char *ReadData)
{
	unsigned short upper_lba, lower_lba;
	unsigned char i;		
	unsigned char *p;
	
	lba = lba * 512;								/*calculate byte address*/
	upper_lba = (lba/65536);
	lower_lba = (lba%65536);

	EnableCard();

	Command_R1(CMD17, upper_lba, lower_lba);					/*read block start at ...,...*/
//	if (response_1 !=0)
//	{
//		return(ERROR_ATAREAD_CMD17);							/*exit if invalid response*/
//	}
	
	if (WaitForSOD() == FALSE)									/*wait for start-of-data (function features time-out)*/
	{
		DisableCard();
		return(FALSE);
	}

	/*read data and exit OK*/
	p=ReadData;
	i=128;
	do
	{
		SSPBUF = 0xff;
		while (!BF);		
		*(p++)=SSPBUF;	
		SSPBUF = 0xff;
		while (!BF);		
		*(p++)=SSPBUF;	
		SSPBUF = 0xff;
		while (!BF);		
		*(p++)=SSPBUF;	
		SSPBUF = 0xff;
		while (!BF);		
		*(p++)=SSPBUF;	
	}
	while(--i);
	//for(lp=0; lp < 512; lp++)					
	//	ReadData[lp] = SPI(0xFF);

	SPI(0xff);
	SPI(0xff);

	DisableCard();
	return(TRUE);
}
    


/*Write: 512 Byte-Mode, this will not work (read MMC and SD-card specs) with any other sector/block size then 512*/
unsigned char AtaWriteSector(unsigned long lba, unsigned char *WriteData)
{
	unsigned short upper_lba, lower_lba, lp;	/*Variable 0...65535*/
	unsigned char i;

	lba = lba * 512;							/*since the MMC and SD cards are byte addressable and the FAT relies on a sector address (where a sector is 512bytes big), we must multiply by 512 in order to get the byte address*/
	upper_lba = (lba/65536);
	lower_lba = (lba%65536);

	Command_R1(CMD24, upper_lba, lower_lba);
	if (response_1 != 0)
	{
		return(FALSE);
	}
	else
	{
		SPI(0xFF);
		SPI(0xFF);
		SPI(0xFE);


		for(lp=0; lp < 512; lp++)
			{
				SPI(WriteData[lp]);
			}
		SPI(255);						// Am ende 2 Byte's ohne Bedeutung senden
		SPI(255);

		i = SPI(0xFF);
//		i &=0b.0001.1111;
//		if (i != 0b.0000.0101) 
//			printf("Write error\n\r");
//		else
//			printf("Write succeeded?");
		while(SPI(0xFF) !=0xFF);		/*wait until the card has finished writing the data*/

		return(TRUE);
	}
}
 

/*************************************************************************************/
/*Internal functions*/
/*************************************************************************************/

unsigned char Card_CMD0(void)
{
	unsigned char	retry_counter;

    retry_counter = 100;						/*this routine is verrrrrrrry important, and sometimes fails on some cards so a retry mechanism is crucial*/
	while(retry_counter--)
	{
		Command_R1(CMD0,0,0);					/*CMD0: Reset all cards to IDLE state*/
		if (response_1 == 1)
			break;

		if (retry_counter == 0)
			return(FALSE);						/*error, quit routine*/
	}
	return(TRUE);
}

unsigned char Card_CMD1(void)
{
	timeout = 0;
	response_1 = 1;
	while(response_1 != 0)
	{
		Command_R1(CMD1,0,0);				/*activate the cards init process*/	
		if (timeout == 10000)				/*timeout mechanism*/
		{
			return(FALSE);
		}
		timeout++;
	}
	return(TRUE);
}


/*Send a command to the SDcard*/
Command_R0(char cmd,unsigned short AdrH,unsigned short AdrL)
{
	crc_7=0;
	SPI(0xFF);				/*flush SPI-bus*/

	SPI(cmd);
	MmcAddCrc7(cmd);		/*update CRC*/
	SPI(AdrH/256);			/*use upper 8 bits (everything behind the comma is discarded)*/
	MmcAddCrc7(AdrH/256);	/*update CRC*/
	SPI(AdrH%256);			/*use lower 8 bits (shows the remaining part of the devision)*/
	MmcAddCrc7(AdrH%256);	/*update CRC*/
	SPI(AdrL/256);			/*use upper 8 bits (everything behind the comma is discarded)*/
	MmcAddCrc7(AdrL/256);	/*update CRC*/
	SPI(AdrL%256);			/*use lower 8 bits (shows the remaining part of the devision)*/
	MmcAddCrc7(AdrL%256);	/*update CRC*/

	crc_7<<=1;				/*shift all bits 1 position to the left, to free position 0*/
	crc_7++;				/*set LSB to '1'*/

	SPI(crc_7);				/*transmit CRC*/
	SPI(0xFF);				/*flush SPI-bus, or int other words process command*/
}


/*Send a command to the SDcard, a one byte response is expected*/
Command_R1(char cmd,unsigned short AdrH,unsigned short AdrL)
{
	Command_R0(cmd, AdrH, AdrL);	/*send command*/
	response_1 = SPI(0xFF);			/*return the reponse in the correct register*/
}


/*Send a command to the SDcard, a two byte response is expected*/
Command_R2(char cmd,unsigned short AdrH,unsigned short AdrL)
{
	Command_R0(cmd, AdrH, AdrL);	/*send command*/
	response_1 = SPI(0xFF);			/*return the reponse in the correct register*/
	response_2 = SPI(0xFF);			
}


/*Send a command to the SDcard, a five byte response is expected*/
Command_R3(char cmd,unsigned short AdrH,unsigned short AdrL)
{
	Command_R0(cmd, AdrH, AdrL);	/*send command*/
	response_1 = SPI(0xFF);			/*return the reponse in the correct register*/
	response_2 = SPI(0xFF);			
	response_3 = SPI(0xFF);			
	response_4 = SPI(0xFF);			
	response_5 = SPI(0xFF);			
}


/*calculate CRC7 checksum*/
void MmcAddCrc7(unsigned char c)
{
	unsigned char i;
	
	i=8;
	do
	{
		crc_7<<=1;
		if(c&0x80)
			crc_7^=0x09;
		if(crc_7&0x80)
			crc_7^=0x09;
		c<<=1;
	}
	while(--i);
}




















