#include <syscall.h>
#include <stdlib.h>
char buf[1000];
int intputchar(char *c);
int intgetchar(char *c);

int main(void) {
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

int intputchar(char *c) {
  asm volatile (
    "syscall"
    :
    : "a"(__NR_write), "D"(1), "S"(c), "d"(1)
    : "memory"
  );
}
int intgetchar(char *c) {
  int ret;
  asm volatile (
    "syscall"
    : "=a"(ret)
    : "a"(__NR_read), "D"(0), "S"(c), "d"(1)
    : "memory"
  );
  if(ret!=1) *c=-1; // -1 == EOF
}
