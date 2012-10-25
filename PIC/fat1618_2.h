#ifndef _FAT16182_H_INCLUDED
#define _FAT16182_H_INCLUDED

struct file2TYPE
{
	unsigned char name[12];   			/*name of file*/
	unsigned short entry;				/*file-entry index in directory table*/
	unsigned short sec;  				/*sector index in file*/
	unsigned short len;					/*total number of sectors in file, 0 if no file*/
	unsigned long cluster;				/*current cluster*/	
};

/*global sector buffer, data for read/write actions is stored here.
BEWARE, this buffer is also used and thus trashed by all other functions*/
extern unsigned char secbuf[512];		/*sector buffer*/

/*constants*/
#define FILESEEK_START			0		/*start search from beginning of directory*/
#define	FILESEEK_NEXT			1		/*find next file in directory*/
#define	FILESEEK_PREV			2		/*find previous file in directory*/

/*functions*/
unsigned char FindDrive2(void);
unsigned char FileSearch2(struct file2TYPE *file, unsigned char mode);
unsigned char FileNextSector2(struct file2TYPE *file);
unsigned char FileRead2(struct file2TYPE *file);

#endif
