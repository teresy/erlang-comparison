#!/bin/bash

cd before-ejabberd-erl-tidy-workspace
git checkout -- .
time erl -noshell -eval 'erl_tidy:dir("",[{keep_unused, true},{backups, false},{auto_list_comp, true}]).' -s init stop &> /dev/null
cd ..

cd before-ejabberd-teresy-workspace
git checkout -- .
time ~/rooibos-future/main -d . -filter .erl -templates ~/rooibos-future/catalogue/erlang/erl-tidy/auto-list-comp-simple-map
echo 'normalizing whitespace with erl_tidy...'
erl -noshell -eval 'erl_tidy:dir("",[{keep_unused, true},{backups, false},{auto_list_comp, true}]).' -s init stop &> /dev/null
cd ..

EQUAL=`./diff-teresy-vs-erl-tidy.sh`

echo "Diffs" ${EQUAL}

cd before-ejabberd-erl-tidy-workspace
git checkout -- .
cd ..

cd before-ejabberd-teresy-workspace
git checkout -- .
cd ..

echo 'The above diff is expected:'
echo "NewEls = [fun xmpp:encode/1(V1) || V1 <- Els], | NewEls = [xmpp:encode(V1) || V1 <- Els], {[encode_item(V2) | {[encode_item(V1) || V2 | || V1 {[encode_item(V3) | {[encode_item(V1) || V3 <- RosterItems], | || V1 <- RosterItems], {[encode_item(V4) | {[encode_item(V1) || V4 | || V1 erl_syntax:fun_expr([erl_syntax:clause([erl_syntax:list([m | erl_syntax:fun_expr([erl_syntax:clause([erl_syntax:list([m | | | JIDs = [fun jid:make/1(V1) | JIDs = [jid:make(V1)"

