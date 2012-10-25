/*
Copyright 2005, 2006, 2007 Dennis van Weeren

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

This is a simple FAT16 handler. It works on a sector basis to allow fastest acces on disk
images.

11-12-2005		-first version, ported from FAT1618.C
*/
				
#include <stdio.h>
#include "ata18.h"
#include "fat1618_2.h"

/*internal global variables*/
static unsigned long fatstart;					/*start LBA of first FAT table*/
static unsigned long datastart;       			/*start LBA of data field*/
static unsigned long dirstart;   				/*start LBA of directory table*/
static unsigned char fatno; 					/*number of FAT tables*/
static unsigned char clustersize;     			/*size of a cluster in blocks*/
static unsigned short direntrys;     			/*number of entry's in directory table*/
unsigned char secbuf[512];						/*sector buffer*/

/*FindDrive checks if a card is present. if a card is present it will check for
a valid FAT16 primary partition*/
unsigned char FindDrive2(void)
{
	unsigned long fatsize;				/*size of fat*/
	unsigned long dirsize;				/*size of directory region in sectors*/
		
	if(!AtaReadSector(0,secbuf))		/*read partition sector*/
		return(0);
	
	if(secbuf[450]!=0x04 && secbuf[450]!=0x06) /*first partition filesystem type: FAT16*/
		return(0);
	                  					/*check signature*/		
	if(secbuf[510]!=0x55 || secbuf[511]!=0xaa)
		return(0);
	
	/*get start of first partition*/
	fatstart=(unsigned long)secbuf[454];
	fatstart+=(unsigned long)secbuf[455]*256;
	fatstart+=(unsigned long)secbuf[466]*65536;
	fatstart+=(unsigned long)secbuf[467]*16777216;
			
	/*read boot sector*/		
	if(!AtaReadSector(fatstart,secbuf))
		return(0);	
	
	/*check for near-jump or short-jump opcode*/
	if(secbuf[0]!=0xe9 && secbuf[0]!=0xeb)
		return(0);
	
	/*check if blocksize is really 512 bytes*/
	if(secbuf[11]!=0x00 || secbuf[12]!=0x02)
		return(0);
	
	/*check medium descriptorbyte, must be 0xf8 for hard drive*/
	if(secbuf[21]!=0xf8)
		return(0);
	
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
	printf("fatsize:%ld\r",fatsize);
	printf("fatno:%d\r",fatno);
	printf("fatstart:%ld\r",fatstart);
	printf("dirstart:%ld\r",dirstart);
	printf("direntrys:%d\r",direntrys);
	printf("datastart:%ld\r",datastart);
	printf("clustersize:%d\r",clustersize);
  	return(1);
}

/*scan directory, yout must pass a file handle to this function
search modes: 0=first,1=next,2=previous*/
unsigned char FileSearch2(struct file2TYPE *file, unsigned char mode)
{
	unsigned long sf,sb;
	unsigned short i;
	unsigned char j;
	
	sb=0;/*buffer is empty*/
	file->len=0;

	if (mode==0)
		file->entry=0;
	else if (mode==1)
		file->entry++;
	else
		file->entry--;

	while(file->entry < direntrys)
	{	
		/*calculate sector and offset*/
		sf = dirstart;
		sf += (file->entry)/16;
	   	i = (file->entry%16)*32;			
	
		/*load sector if not in buffer*/
		if (sb != sf)
		{
			sb = sf;
			if (!AtaReadSector(sb,secbuf))
				return(0);	
		}	
		
		/*check if valid file entry*/
		if (secbuf[i]!=0x00 && secbuf[i]!=0xe5 && secbuf[i]!=0x2e)
	    	/*and valid attributes*/
	    	if ((secbuf[i+11]&0x1a)==0x00)
			{
				/*copy name*/
				for (j=0;j<11;j++)           	
					file->name[j] = secbuf[i+j];
				file->name[j] = 0x00;
				
				file->attributes = secbuf[i+11];

				/*get length of file*/
				file->len = *((unsigned long*)&secbuf[i+28]);	//it only works when using little endian long representation
						
				/*get first cluster of file*/
				file->cluster=(unsigned long)secbuf[i+26]+((unsigned long)secbuf[i+27]*256);
				
				/*reset sector index*/
				file->sec=0;
						
				return(1);
			}
		if((mode==0) || (mode==1))
			file->entry++;
		else
			file->entry--;
	}		
	return(0);
}

/*point to next sector in file*/
unsigned char FileNextSector2(struct file2TYPE *file)
{
	unsigned long sb;
	unsigned short i;
	
	/*increment sector index*/
	file->sec++;
	
	/*if we are now in another cluster, look up cluster*/
	if((file->sec%clustersize)==0)
	{
		/*calculate sector that contains FAT-link*/
		sb=fatstart;
		sb+=(file->cluster/256);
		/*calculate offset*/
		i=(file->cluster%256);
		i*=2;
		
		/*read sector of FAT*/
		if(!AtaReadSector(sb,secbuf))
			return(0);
			
		/*get FAT-link*/
		file->cluster=((unsigned long)secbuf[i+1]*256)+(unsigned long)secbuf[i];					
	}

	return(1);
}

/*read sector into buffer*/
unsigned char FileRead2(struct file2TYPE *file)
{
	unsigned long sb;
	
	sb=datastart;						/*start of data in partition*/
	sb+=clustersize*(file->cluster-2);	/*cluster offset*/
	sb+=(file->sec%clustersize); 		/*sector offset in cluster*/
										/*read sector from drive*/
	if(!AtaReadSector(sb,secbuf))
		return(0);
	else
		return(1);
}

/*write buffer to sector*/
unsigned char FileWrite2(struct file2TYPE *file)
{
	unsigned long sb;
	
	sb=datastart;						/*start of data in partition*/
	sb+=clustersize*(file->cluster-2);	/*cluster offset*/
	sb+=(file->sec%clustersize); 		/*sector offset in cluster*/
										/*write sector from drive*/
	if(!AtaWriteSector(sb,secbuf))
		return(0);
	else
		return(1);
}


















/***************************************************************************************************************************************/
/***************************************************************************************************************************************/
/***************************************************************************************************************************************/
/***************************************************************************************************************************************/
/***************************************************************************************************************************************/


