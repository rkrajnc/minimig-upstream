What has changed?

Mainly the PIC18 code has changed to support encrypted roms, fix some bugs and add error posting.
Inside the core, only the 68000 bootrom has changed.

bugs:
During the development of the encrypted rom routines, I found out that the fifo handling inside the floppy module is broken. As a result, too much or too little (missing bytes) data is read during a floppy read. This is (hopefully) the reason a lot of games wont load properly. I am looking into it.

Dennis van Weeren
27-04-2008
