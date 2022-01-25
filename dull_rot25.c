#include <syscall.h>
#include <stdlib.h>
static char buf[1000];
static int intputchar(char *c);
static int intgetchar(char *c);

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

#ifdef BIT64
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

#else
int intputchar(char *c) {
  asm volatile (
    "int $0x80"
    :
    : "a"(__NR_write), "b"(1), "c"(c), "d"(1)
    : "memory"
  );
}
int intgetchar(char *c) {
  int ret;
  asm volatile (
    "int $0x80"
    : "=a"(ret)
    : "a"(__NR_read), "b"(0), "c"(c), "d"(1)
    : "memory"
  );
  if(ret!=1) *c=-1; // -1 == EOF
}
#endif
