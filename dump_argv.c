#include <stdio.h>

int main(int argc, char **argv) {
  printf("argc = %d\n", argc);
  for(int i=0; i<argc; i++) {
    printf("argv[%d]: ", i);
    for(int j=0; argv[i][j]; j++) {
      printf("%c(%d) ", argv[i][j], argv[i][j]);
    }
    printf("\n");
  }
}
