>,[>,]<           read as many chars as possible
[                 while ArrayA last cell is not null
                  Move it after rightmost 0 delimiter of ArrayB
  [-              decrase by 1
    >>[>]>+       go to target and increase by one
    <<[<]<        go back to source
  ]               and loop
  >>[>]>[-<+>]    then move copied value after ArrayB
  <[<]>[[-<+>]>]  shift ArrayB to the left
  <<[<]<          go back to ArrayA last cell
]>                loop, and go back to left delimiter of revert(Array) 
>[.>]             iterate on the array ; print and move
