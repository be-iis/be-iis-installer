// SPDX-License-Identifier: GPL-2.0-or-later
#include <errno.h>
#include <fcntl.h>
#include <linux/spi/spidev.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define PAGE 16
#define EXPECTED_ID 0x012b9043U

static int xfer(int fd, uint8_t *tx, uint8_t *rx, size_t n) {
 struct spi_ioc_transfer t={.tx_buf=(unsigned long)tx,.rx_buf=(unsigned long)rx,.len=n,.speed_hz=1000000,.bits_per_word=8};
 return ioctl(fd,SPI_IOC_MESSAGE(1),&t)==(int)n ? 0 : -1;
}
static uint32_t cmd_read(int fd,uint8_t op) {
 uint8_t tx[8]={op,0,0,0,0,0,0,0},rx[8]={0};
 if(xfer(fd,tx,rx,8)) { perror("SPI"); exit(1); }
 return ((uint32_t)rx[4]<<24)|((uint32_t)rx[5]<<16)|((uint32_t)rx[6]<<8)|rx[7];
}
static void cmd(int fd,uint8_t op,uint8_t a,uint8_t b,uint8_t c) {
 uint8_t tx[4]={op,a,b,c},rx[4]={0}; if(xfer(fd,tx,rx,4)){perror("SPI");exit(1);}
}
static uint32_t status(int fd) { return cmd_read(fd,0x3c); }
static void wait_ready(int fd) {
 for(int i=0;i<2000;i++){ uint32_t s=status(fd); if(!(s&(1U<<12))){if(s&(1U<<13)){fprintf(stderr,"MachXO2 FAIL: %08x\n",s);exit(1);}return;} usleep(5000); }
 fprintf(stderr,"MachXO2 busy timeout\n"); exit(1);
}
int main(int ac,char **av) {
 if(ac!=4 || strcmp(av[1],"--program")) { fprintf(stderr,"usage: %s --program /dev/spidev0.0 firmware.bit\n",av[0]); return 2; }
 int spi=open(av[2],O_RDWR), in=open(av[3],O_RDONLY); if(spi<0||in<0){perror("open");return 1;}
 uint8_t mode=SPI_MODE_0,bits=8; uint32_t speed=1000000;
 if(ioctl(spi,SPI_IOC_WR_MODE,&mode)||ioctl(spi,SPI_IOC_WR_BITS_PER_WORD,&bits)||ioctl(spi,SPI_IOC_WR_MAX_SPEED_HZ,&speed)){perror("SPI setup");return 1;}
 uint32_t id=cmd_read(spi,0xe0); printf("MachXO2 IDCODE: 0x%08x\n",id);
 if(id!=EXPECTED_ID){fprintf(stderr,"unexpected device ID\n");return 1;}
 printf("Status: 0x%08x\n",status(spi));
 cmd(spi,0xc6,0x08,0x00); wait_ready(spi);
 cmd(spi,0x0e,0x04,0x00); wait_ready(spi);
 cmd(spi,0x46,0,0,0);
 uint8_t page[PAGE],tx[4+PAGE],rx[4+PAGE]; size_t n; unsigned long pages=0;
 while((n=read(in,page,PAGE))){ if(n<PAGE){fprintf(stderr,"bitstream size is not a multiple of 16 bytes\n");return 1;} tx[0]=0x70;tx[1]=0;tx[2]=0;tx[3]=1;memcpy(tx+4,page,PAGE);memset(rx,0,sizeof(rx));if(xfer(spi,tx,rx,sizeof(tx))){perror("program");return 1;} pages++; }
 if(errno){perror("read");return 1;} wait_ready(spi); cmd(spi,0x5e,0,0,0); wait_ready(spi); cmd(spi,0x79,0,0,0); usleep(500000); wait_ready(spi);
 printf("Programmed %lu pages; status: 0x%08x\n",pages,status(spi)); return 0;
}
