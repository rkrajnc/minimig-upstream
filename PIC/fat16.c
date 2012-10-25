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

This is a simple FAT16 handler. It works on a sector basis to allow fast acces to disk
images.

11-12-2005		-first version, ported from FAT1618.C
29-09-2007		-(Jan) fixed a small bug important bug in the FATSTART calculation (566 and 567 instead of 556 and 557) depending on your card it should not cause to much trouble...
				-(Jan) renamed fat1618_2 to fat16 and renamed ata18 to ata (the old names where only confusing)
				-(Jan) And also FindDrive2,FileSearch2,FileNextSector2 and FileRead2 were renamed to FindDrive,FileSearch,FileNextSector and FileRead
20-01-2008		-(Dennis) ported back changes made by Jan Derogee to Minimig, cleaned up a little bit
21-01-2008		-(Dennis) fixed bug in determination of file length
				-(Dennis) added support for extended partitions
27-01-2008		-(Dennis) added len2 in struct fileTYPE, len2 holds size of file in bytes
27-04-2008		-(Dennis) removed some debug output
*/

/*includes*/
#include <stdio.h>
#include "ata.h"
#include "fat16.h" 

/*constants*/
#define FALSE 0									/*FALSE*/
#define	TRUE 1									/*TRUE*/

/*globals*/
static unsigned long fatstart;					/*start LBA of first FAT table*/
static unsigned long datastart;       			/*start LBA of data field*/
static unsigned long dirstart;   				/*start LBA of directory table*/
static unsigned char fatno; 					/*number of FAT tables*/
static unsigned char clustersize;     			/*size of a cluster in blocks*/
static unsigned short direntrys;     			/*number of entry's in directory table*/
unsigned char secbuf[512];						/*sector buffer*/


/*****************************************************************************************************************/
/*****************************************************************************************************************/

/*FindDrive checks if a card is present. if a card is present it will check for
a valid FAT16 primary partition*/
unsigned char FindDrive(void)
{
	unsigned long fatsize;				/*size of fat*/
	unsigned long dirsize;				/*size of directory region in sectors*/
		
	if(!AtaReadSector(0,secbuf))		/*read partition sector*/
		return(FALSE);
	
										/*check partition type*/
	if(secbuf[450]!=0x04 && secbuf[450]!=0x05 && secbuf[450]!=0x06)
		return(FALSE);
	                  					/*check signature*/		
	if(secbuf[510]!=0x55 || secbuf[511]!=0xaa)
		return(FALSE);
	
	/*get start of first partition*/
	fatstart=(unsigned long)secbuf[454];		/*get start of first partition*/
	fatstart+=(unsigned long)secbuf[455]*256;
	fatstart+=(unsigned long)secbuf[456]*65536;
	fatstart+=(unsigned long)secbuf[457]*16777216;
			
	/*read boot sector*/		
	if(!AtaReadSector(fatstart,secbuf))
		return(FALSE);	
	
	/*check for near-jump or short-jump opcode*/
	if(secbuf[0]!=0xe9 && secbuf[0]!=0xeb)
		return(FALSE);
	
	/*check if blocksize is really 512 bytes*/
	if(secbuf[11]!=0x00 || secbuf[12]!=0x02)
		return(FALSE);
	
	/*check medium descriptorbyte, must be 0xf8 for hard drive*/
	if(secbuf[21]!=0xf8)
		return(FALSE);
	
	/*calculate drive's parameters from bootsector, first up is size of directory*/
	direntrys=secbuf[17]+(secbuf[18]*256);	
	dirsize=((direntrys*32)+511)/512;                  
	
	/*calculate start of FAT,size of FAT and number of FAT's*/
	fatstart=fatstart+secbuf[14]+(secbuf[15]*256);	
	fatsize=secbuf[22]+(secbuf[23]*256);
	fatno=secbuf[16];
	
	/*calculate start of directory*/
	dirstart=fatstart+(fatno*fatsize);
	
	/*get clustersize*/
	clustersize=secbuf[13];
	
	/*calculate start of data*/
	datastart=dirstart+dirsize;  
    	    
    /*some debug output*/
	/*printf("fatsize:%ld\r\n",fatsize);
	printf("fatno:%d\r\n",fatno);
	printf("fatstart:%ld\r\n",fatstart);
	printf("dirstart:%ld\r\n",dirstart);
	printf("direntrys:%d\r\n",direntrys);
	printf("datastart:%ld\r\n",datastart);
	printf("clustersize:%d\r\n",clustersize);*/
  	return(TRUE);
}

/*scan directory, yout must pass a file handle to this function
search modes: FILESEEK_START,FILESEEK_NEXT,FILESEEK_PREV*/
unsigned char FileSearch(struct fileTYPE *file, unsigned char mode)
{
	unsigned long sf,sb;
	unsigned short i;
	unsigned char j;
	
	sb=0;/*buffer is empty*/
	if(mode==0)
		file->entry=0;
	else if(mode==1)
		file->entry++;
	else
		file->entry--;

	while(file->entry<direntrys)
	{	
		/*calculate sector and offset*/
		sf=dirstart;
		sf+=(file->entry)/16;
	   	i=(file->entry%16)*32;			
	
		/*load sector if not in buffer*/
		if(sb!=sf)
		{
			sb=sf;
			if(!AtaReadSector(sb,secbuf))
				return(FALSE);	
		}	
		
		/*check if valid file entry*/
		if(secbuf[i]!=0x00 && secbuf[i]!=0xe5 && secbuf[i]!=0x2e)
	    	/*and valid attributes*/
	    	if((secbuf[i+11]&0x1a)==0x00)
			{
				/*copy name*/
				for(j=0;j<11;j++)           	
					file->name[j]=secbuf[i+j];
				file->name[j]=0x00;
				
				/*get length of file in sectors, maximum is 16Mbytes*/
				file->len=(unsigned long)secbuf[i+28];
				file->len+=(unsigned short)secbuf[i+29]*256;
				file->len+=511;
				file->len/=512;
				file->len+=(unsigned long)secbuf[i+30]*128;
						
				/*get length of file in bytes*/
				file->len2=(unsigned long)secbuf[i+28];
				file->len2+=(unsigned long)secbuf[i+29]<<8;
				file->len2+=(unsigned long)secbuf[i+30]<<16;
				file->len2+=(unsigned long)secbuf[i+31]<<24;
						
				/*get first cluster of file*/
				file->cluster=(unsigned long)secbuf[i+26]+((unsigned long)secbuf[i+27]*256);
				
				/*reset sector index*/
				file->sec=0;
						
				return(TRUE);
			}
		if((mode==FILESEEK_START) || (mode==FILESEEK_NEXT))
			file->entry++;
		else
			file->entry--;
	}
	file->len=0;		
	return(FALSE);
}

/*point to next sector in file*/
unsigned char FileNextSector(struct fileTYPE *file)
{
	unsigned long sb;
	unsigned short i;
	
	file->sec++;						/*increment sector index*/
	if((file->sec%clustersize)==0)		/*if we are now in another cluster, look up cluster*/
	{
		sb=fatstart;					/*calculate sector that contains FAT-link*/
		sb+=(file->cluster/256);
		i=(file->cluster%256);			/*calculate offset*/
		i*=2;
		
		if(!AtaReadSector(sb,secbuf))	/*read sector of FAT*/
			return(FALSE);
			
		file->cluster=((unsigned long)secbuf[i+1]*256)+(unsigned long)secbuf[i];	/*get FAT-link*/
	}

	return(TRUE);
}

/*read sector into buffer*/
unsigned char FileRead(struct fileTYPE *file)
{
	unsigned long sb;
	
	sb=datastart;						/*start of data in partition*/
	sb+=clustersize*(file->cluster-2);	/*cluster offset*/
	sb+=(file->sec%clustersize); 		/*sector offset in cluster*/
										/*read sector from drive*/
	if(!AtaReadSector(sb,secbuf))
		return(FALSE);
	else
		return(TRUE);
}


/***************************************************************************************************************************************/
/***************************************************************************************************************************************/
/***************************************************************************************************************************************/
/***************************************************************************************************************************************/
/***************************************************************************************************************************************/


