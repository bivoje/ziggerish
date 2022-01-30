#include <syscall.h>
#include <unistd.h> // read/write
#include <stdlib.h> // exit

static char buf[1000];
static void intputchar(char *c);
static void intgetchar(char *c);

void main(void) {
  char *ptr = buf;
  ++*ptr;
  while(*ptr) {
    ++ptr;
    intgetchar(ptr);
    --*ptr;
    intputchar(ptr);
    ++*ptr;
    ++*ptr;
  }
  exit(0);
}

void intputchar(char *c) {
  int x = write(1, c, 1);
}

void intgetchar(char *c) {
  int ret = read(0, c, 1);
  if(ret!=1) *c=-1; // -1 == EOF
}
