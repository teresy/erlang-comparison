#!/bin/bash

cd ejabberd-erl-tidy-workspace
git checkout -- .
time erl -noshell -eval 'erl_tidy:dir("",[{keep_unused, true},{backups, false},{auto_list_comp, true}]).' -s init stop &> /dev/null
cd ..

cd ejabberd-teresy-workspace
git checkout -- .
time ~/rooibos-future/main -d . -filter .erl -templates ~/rooibos-future/catalogue/erlang/tidier/append-4.3
cd ..

EQUAL=`diff -y --suppress-common-lines ejabberd-{erl-tidy,teresy}-workspace/mod_pubsub.erl`

echo "Diffs" ${EQUAL}

cd ejabberd-erl-tidy-workspace
git checkout -- .
cd ..

cd ejabberd-teresy-workspace
git checkout -- .
cd ..

