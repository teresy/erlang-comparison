#!/bin/bash

cd before-ejabberd-erl-tidy-workspace

find . -name "*.erl" |\
 xargs -L 1 -I % \
 diff -W $(tput cols) -y --suppress-common-lines % ../before-ejabberd-teresy-workspace/%

cd --
