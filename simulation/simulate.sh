#!/bin/bash
# ANSI terminal sequences:
_esc=''
_csi="${_esc}["
_vt_NORM="${_csi}0m"		# Normal text.
_vt_HI="${_csi}1m"              # Bold text.
_vt_LOW="${_csi}2m"             # half-bright.
_vt_UNDER="${_csi}4m"           # Underscored text.
_vt_BLINK="${_csi}5m"           # Blinking text.
_vt_INV="${_csi}7m"		# Inverse text.
_vt_LOW_RED="${_csi}2;31m"
_vt_LOW_GREEN="${_csi}2;32m"
_vt_LOW_YELLOW="${_csi}2;33m"
_vt_LOW_BLUE="${_csi}2;34m"
_vt_LOW_MAGENTA="${_csi}2;35m"
_vt_LOW_CYAN="${_csi}2;36m"
_vt_LOW_WHITE="${_csi}2;37m"

# Defaults
site=site.com
app=app
main=stable
stage=stage
prod_user=prod
rel_1=r20110420
rel_2=r20110427
rels="$rel_1 $rel_2"
task_1=t1234
task_2=t5678
t1234_rel="$rel_1"
t1234_dev=alice
t5678_rel="$rel_2"
t5678_dev=bob
tasks="$task_1 $task_2"
prod_dir=export/web
work_dir=export
user_dir=$work_dir/u
task_dir=$work_dir/t
rel_dir=$work_dir/r
pause=
#pause=1

_set_task() {
  { set +x; } 1>/dev/null 2>&1
  echo "..."
  task="$1"
  eval rel=\$${task}_rel dev=\$${task}_dev
  set +x
}

# Overrides
for expr in "$@"; do eval "$expr"; done

# Rewrite output:
if [ -z "$_REWRITING_OUTPUT" ]
then
  # set -x
  exec 3>&2
  "$0" _REWRITING_OUTPUT=1 "$@" 2>&1 | 
  sed \
  -e "s#file:////.*/gh/#git@git.${site}/#g" \
  -e "s#\(comment \)\(.*\)#\\1${_vt_HI}${_vt_UNDER}\\2${_vt_NORM}#"
  exit $?
fi

color_=RED
color_somebody=RED
color_alice=GREEN
color_bob=YELLOW
color_clara=BLUE
color_dave=MAGENTA
eval color_${prod_user}=CYAN

_vt_PROMPT_="${_vt_LOW_RED}"

unset EMAIL
# avoid RVM madness
unset -f cd; alias cd='builtin cd' 

ssh() {
  { set +x; } 1>/dev/null 2>&1
  local user_host="$1"
  user="${user_host//@*/}"
  host="${user_host//*@/}"
  export GIT_AUTHOR_NAME="${user}"
  export GIT_AUTHOR_EMAIL="${user}@$site"
  export GIT_COMMITTER_NAME="${user}"
  export GIT_COMMITTER_EMAIL="${user}@$site"
  pushd "host/$host" 1>/dev/null
  eval "prompt_color=\"\${color_$user}\""
  eval "_vt_PROMPT=\"\${_vt_LOW_$prompt_color}\""
  PS4=" ${_vt_PROMPT}$user_host >${_vt_NORM} "
  set -x
}

default_PS4=" ${_vt_PROMPT_}>${_vt_NORM} "
PS4="$default_PS4"
logout() {
  { set +x; } 1>/dev/null 2>&1
  popd 1>/dev/null
  echo "  LOGGED OUT"
  echo ""
  user=
  host=
  PS4="$default_PS4"
  set -x
}

comment() {
  { set +x; } 1>/dev/null 2>&1
  # echo "pause=$pause"
  if [ -n "$pause" ]; then
    # echo "      # ${_vt_INV}[ENTER]${_vt_NORM}: " 1>&3
    read line
  fi
  : "$@"
  set -x
}

vi() {
  { set +x; } 1>/dev/null 2>&1
  cat - >"$1"
  echo "${PS4}cat $1"
  cat "$1"
  set -x
}

# STUBS

mail() {
  : ...
}
rake() { 
  : ...
}
task() {
  : ...
}

##########################################
# Pre-conditions
#

set -e
# trap '{ set +x; } >/dev/null 2>&1; echo "$0: exit $?: $BASH_COMMAND"' EXIT

rm -rf gh host
mkdir -p host/{localhost,alice.dev,bob.dev,clara.qa,dave.dev,$main.qa,$stage.prod}

dir="$(cd $(dirname $0) && /bin/pwd)"
gh="file:///$dir/gh"

ssh somebody@localhost
cd ../..

######################################################################
comment "# Setup simulation"

comment "## Create main app repo on git.$site."
(
mkdir -p gh/$main/$app
cd gh/$main/$app
git init
vi foo.sh <<EOF
#!/bin/bash
echo "\$0 std"
EOF
chmod +x foo.sh
git add foo.sh

vi bar.sh <<EOF
#!/bin/bash
echo "\$0 std"
EOF
chmod +x bar.sh
git add bar.sh

vi test.sh <<EOF
#!/bin/bash
PS4="\$0: "
trap ': exit \$?: \$BASH_COMMAND' EXIT
set -xe
./foo.sh > result.out
fgrep -q './foo.sh std' result.out
./bar.sh > result.out
fgrep -q './bar.sh std' result.out
rm result.out
: OK
EOF
chmod +x test.sh
git add test.sh

./test.sh

git commit -m "Initial $main $app." -a
) || exit 1

comment "## Devs (alice, bob, dave) clone main repo on git.$site."
for user in alice bob dave
do
(
mkdir -p gh/$user
cd gh/$user
git clone $gh/$main/$app
) || exit 1
done

######################################################################
comment "# Run Simulation"

comment "## Initial production deployment."
ssh $prod_user@$stage.prod
mkdir -p $prod_dir
cd $prod_dir
git clone $gh/$main/$app
cd $app
git checkout master
# ./test.sh
rake push
logout

comment "## Devs (alice, bob, dave) clone their git.$site repos to local machines."
for user in alice bob dave
do
  ssh $user@$user.dev
  mkdir -p $user_dir/$user
  cd $user_dir/$user
  git clone $gh/$user/$app
  cd $app
  git remote add -f $main $gh/$main/$app
  logout
done

for rel in $rels
do 
comment "## RelEng (dave) creates release branch $rel in $gh/$main/$app."
ssh dave@dave.dev
mkdir -p $rel_dir/$rel
cd $rel_dir/$rel
git clone $gh/$main/$app
cd $app
git branch $rel
git checkout $rel
git push origin $rel
logout
done

for t in $task_1 $task_2
do
_set_task $t
comment "## Dev ($dev) works on Task ${task} scheduled for Release ${rel}."
ssh $dev@$dev.dev
cd $user_dir/$dev/$app

comment "### Dev ($dev) creates task branch ${task}."
git checkout master
git pull origin master
git branch $task
git checkout $task
git branch --color

comment "### Dev ($dev) checks for working tests before changes."
./test.sh
logout

done

_set_task $task_1
comment "### Dev ($dev) alters tests before changing code to Task $task spec."
ssh $dev@$dev.dev
cd $user_dir/$dev/$app
vi test.sh <<EOF
#!/bin/bash
PS4="\$0: "
trap ': exit \$?: \$BASH_COMMAND' EXIT
set -xe
./foo.sh > result.out
fgrep -q './foo.sh $task' result.out
./bar.sh > result.out
fgrep -q './bar.sh std' result.out
rm result.out
: OK
EOF
git diff --color test.sh
./test.sh || comment "Expected test failure: exit $?"
git commit -m "Test for $task feature" -a

comment "### Dev ($dev) attempts to change code according to Task $task spec."
vi foo.sh <<EOF
#!/bin/bash
echo "\$0 $task"
EOF
./test.sh && comment "Test passes: exit $?"
git commit -m "Added $task feature." -a

logout
_set_task $task_1
comment "## Dev ($dev) prepares task candidate for QA and release."
ssh $dev@$dev.dev
cd $user_dir/$dev/$app

comment "### Dev ($dev) pulls down main master and creates task candidate branch for Task ${task}."
git checkout master
git pull origin master
git branch ${task}c1
git checkout ${task}c1
comment "### Dev ($dev) merges task work into task candidate branch."
git merge --squash ${task}
git commit -m "${task}: foo.sh: output $task." -a
git log
git push origin ${task}c1
comment "### Dev ($dev) marks task completed."
task $task completed
mail -s "${task}: Task candidate ${task}c1 completed and ready for QA." qa@$site
logout

comment "## QA (clara) tests task candidate ${task}c1."
ssh clara@clara.qa
mkdir -p $task_dir/${task}c1
cd $task_dir/${task}c1
git clone $gh/$dev/$app
cd $app
comment "### QA checkout ${task}c1."
git checkout ${task}c1
git branch --color
comment "### QA (clara) runs tests."
./test.sh
bash ./foo.sh > result.out && fgrep -q "./foo.sh $task" result.out

comment "### QA (clara) marks task approved, tags task candidate."
task 1234 approved
git tag -a -m "${task}: $user approved ${task}c1 as ${task}a1." ${task}a1
git tag -l
git push --tags
mail -s '${task}: $user approved ${task}c1 as ${rel}a1.' $dev@$site rel@$site

logout
_set_task $task_2

comment "### Dev ($dev) alters tests before changing code to Task $task spec."
vi test.sh <<EOF
#!/bin/bash
PS4="\$0: "
trap ': exit \$?: \$BASH_COMMAND' EXIT
set -xe
./foo.sh param > result.out
fgrep -q './foo.sh std' result.out
./bar.sh param > result.out
fgrep -q './bar.sh $task param' result.out
rm result.out
: OK
EOF
git diff --color test.sh
./test.sh || comment "Expected test failure: exit $?"
git commit -m "Test for parameter feature" -a

comment "### Dev ($dev) attempts to change code according to spec (TYPO)."
vi bar.sh <<EOF
#!/bin/bash
echo "\$0 $task TYPO \$1"
EOF
git commit -m "Added parameter feature." -a
./test.sh || comment "Unexpected test failure: exit $?"

comment "### Dev ($dev) fixes code to task spec."
vi bar.sh <<EOF
#!/bin/bash
echo "\$0 $task \$1"
EOF
git diff --color bar.sh
./test.sh && comment "Test passes: exit $?"
git commit -m "Fixed typo." -a

comment "### Dev ($dev) rebases branch from main repo master."
git fetch $main
git merge $main/master

#comment "### Dev ($dev) checks tests again."
#./test.sh || comment "Unexpected test failure: exit $?"

# git log -p
comment "### Dev ($dev) pushes working task branch to personal git.$site repo."
git push origin $task

logout
_set_task $task_1
comment "## Dev ($dev) prepares task candidate for QA and release."
ssh $dev@$dev.dev
cd $user_dir/$dev/$app

comment "### Dev ($dev) pulls down main master and creates task candidate branch for Task ${task}."
git checkout master
git pull origin master
git branch ${task}c1
git checkout ${task}c1
comment "### Dev ($dev) merges task work into task candidate branch."
git merge --squash ${task}
git commit -m "${task}: foo.sh: output $task." -a
git log
git push origin ${task}c1
comment "### Dev ($dev) marks task completed."
task $task completed
mail -s "${task}: Task candidate ${task}c1 completed and ready for QA." qa@$site
logout

comment "## QA (clara) tests task candidate ${task}c1."
ssh clara@clara.qa
mkdir -p $task_dir/${task}c1
cd $task_dir/${task}c1
git clone $gh/$dev/$app
cd $app
comment "### QA checkout ${task}c1."
git checkout ${task}c1
git branch --color
comment "### QA (clara) runs tests."
bash ./test.sh
bash ./foo.sh > result.out && fgrep -q "./foo.sh $task" result.out

comment "### QA (clara) marks task approved, tags task candidate."
task 1234 approved
git tag -a -m "${task}: $user approved ${task}c1 as ${task}a1." ${task}a1
git tag -l
git push --tags
mail -s '${task}: $user approved ${task}c1 as ${rel}a1.' $dev@$site rel@$site
logout

comment "## RelEng (dave) merges approved Task ${task} into Release ${rel} branch."
ssh dave@dave.dev
cd $rel_dir/$rel/$app
git remote add -f $dev $gh/$dev/$app
git checkout $rel
git merge ${task}a1
git commit -m "${rel}: ${task}" -a || : Fast-forward is OK
git push origin $rel
logout

comment "## Integration Test of Release Candidate (RC)."
ssh $prod_user@$main.qa
mkdir -p $rel_dir/$rel
cd $rel_dir/$rel
git clone $gh/$main/$app
cd $app
git pull
git checkout ${rel}
bash ./test.sh
git tag -a -m "${rel}: Release Candidate ${rel}c1." ${rel}c1
git tag -l
git push --tags origin
mail -c "${rel}: Release Candiate ${rel}c1 tagged." release@$site
logout

comment "## RelEng (dave) merges RC into main head and tags it."
ssh dave@dave.dev
cd $rel_dir/$rel/$app
comment "### RelEng (dave) updates from master."
git fetch
git checkout master
git pull origin master
comment "### RelEng (dave) merges rel candiate ${rel}c1 and tags it into $main master."
git merge ${rel}c1
git commit -m "${rel}: Release Candidate ${rel}c1 as ${rel}p1." -a || : Fast-forward is OK
git tag -a -m "${rel}: Release Candidate ${rel}p1." ${rel}p1
git tag -l
git push --tags origin
mail -c "${rel}: Release Candidate ${rel}c1 merged to master and tagged ${rel}p1" release@$site production@$site
logout

comment "## Ops deploys ${rel}p1 tag."
ssh $prod_user@$stage.prod
cd $prod_dir/$app

git checkout master
bash ./test.sh
bash ./foo.sh option > result.out; fgrep -q './foo.sh std' result.out
git log

comment "### Ops pulls new tags and checkout ${rel}p1."
git tag -l
git fetch
git tag -l
git checkout ${rel}p1 > result.out 2>&1
fgrep -q "You are in 'detached HEAD' state." result.out
git log

comment "### Ops runs sanity check."
bash ./test.sh
bash ./foo.sh option > result.out; fgrep -q "./foo.sh $task_1" result.out

comment "### Ops pushes ${rel}p1 tag."
rake push tag="${rel}p1"
mail -c "${rel}: Released ${rel}p1." production@$site
logout

comment "# Release complete!"

