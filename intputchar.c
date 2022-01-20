#include <sys/types.h>

/**/
//#include <asm/unistd.h>
#include <syscall.h>
ssize_t intputchar(char c) {
    ssize_t ret;
    asm volatile (
        "syscall"
        : "=a" (ret)
        : "0"(__NR_write), "D"(1), "S"(&c), "d"(1)
        : "memory"
    );
    return ret;
}
//*/

/*
// i386-64 Linux
#include <asm/unistd.h>      // compile with -m64 for 64 bit call numbers
//#define __NR_write 1
ssize_t my_write(int fd, const void *buf, size_t size)
{
    ssize_t ret;
    asm volatile
    (
        "syscall"
        : "=a" (ret)
        : "0"(__NR_write), "D"(fd), "S"(buf), "d"(size)
        : "memory"    // the kernel dereferences pointer args
    );
    return ret;
}
*/

/*
// i386 Linux
#include <asm/unistd.h>      // compile with -m32 for 32 bit call numbers
//#define __NR_write 4
ssize_t my_write(int fd, const void *buf, size_t size)
{
    ssize_t ret;
    asm volatile
    (
        "int $0x80"
        : "=a" (ret)
        //: "0"(__NR_write), "b"(fd), "c"(buf), "d"(size)
        : "0"(__NR_write), "b"(fd), "c"(buf), "d"(size)
        : "memory"    // the kernel dereferences pointer args
    );
    return ret;
}
*/

#include <stdio.h>
int main() {
  printf("%d\n", __NR_write);
  char message[] = "hello, how are you\n";
  int count = 0;
  for(char *p = message; *p; p++) {
    count += intputchar(*p);
    //count += my_write(0, p, 1);
  }

  return count;
}
