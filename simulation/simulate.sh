#!/bin/bash
# Defaults
site=site.com
app=app
main=stable
stage=stage
prod_user=prod
rel=r20110427
task=t1234
prod_dir=export/web
work_dir=export
user_dir=$work_dir/u
task_dir=$work_dir/t
rel_dir=$work_dir/r
pause=
#pause=1

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
gh=file:///$dir/gh

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

comment "## Devs clone main repo on git.$site."
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

comment "## Devs clone their git.$site repos to local machines."
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

comment "## RelEng creates release branch $rel in $gh/$main/$app."
ssh dave@dave.dev
mkdir -p $rel_dir/$rel
cd $rel_dir/$rel
git clone $gh/$main/$app
cd $app
git branch $rel
git checkout $rel
git push origin $rel
logout

comment "## Dev works on Task ${task}."
ssh alice@alice.dev
cd $user_dir/alice/$app

comment "### Dev creates task branch ${task}."
git checkout master
git pull origin master
git branch $task
git checkout $task
git branch --color

comment "### Dev checks for working tests before changes."
./test.sh

comment "### Dev alters tests before changing code to task spec."
vi test.sh <<EOF
#!/bin/bash
PS4="\$0: "
trap ': exit \$?: \$BASH_COMMAND' EXIT
set -xe
./foo.sh param > result.out
fgrep -q './foo.sh 1234 param' result.out
./bar.sh > result.out
fgrep -q './bar.sh std' result.out
rm result.out
: OK
EOF
git diff --color test.sh
./test.sh || comment "Expected test failure: exit $?"
git commit -m "Test for parameter feature" -a

comment "### Dev attempts to change code according to spec (TYPO)."
vi foo.sh <<EOF
#!/bin/bash
echo "\$0 1234 TYPO \$1"
EOF
git commit -m "Added parameter feature." -a
./test.sh || comment "Unexpected test failure: exit $?"

comment "### Dev rebases branch from main repo master."
git fetch $main
git merge $main/master

comment "### Dev fixes code to task spec."
vi foo.sh <<EOF
#!/bin/bash
echo "\$0 1234 \$1"
EOF
git diff --color foo.sh
./test.sh && comment "Test passes: exit $?"
git commit -m "Fixed typo." -a

# git log -p
comment "### Dev pushes working task branch to personal git.$site repo."
git push origin $task
logout

comment "## Dev prepares task candidate for QA and release."
ssh alice@alice.dev
cd $user_dir/alice/$app
comment "### Dev pulls down main master and creates task candidate branch."
git checkout master
git pull origin master
git branch ${task}c1
git checkout ${task}c1
comment "### Dev merges task work into task candidate branch."
git merge --squash ${task}
git commit -m "${task}: foo.sh: output 1234 with parameter." -a
git log
git push origin ${task}c1
comment "### Dev marks task completed."
task 1234 completed
mail -s "${task}: Task candidate ${task}c1 completed and ready for QA." qa@$site
logout

comment "## QA tests task candidate ${task}c1."
ssh clara@clara.qa
mkdir -p $task_dir/${task}c1
cd $task_dir/${task}c1
git clone $gh/alice/$app
cd $app
comment "### QA checkout ${task}c1."
git checkout ${task}c1
git branch --color
comment "### QA runs tests."
./test.sh
bash ./foo.sh option > result.out && fgrep -q './foo.sh 1234 option' result.out

comment "### QA marks task approved, tags task candidate."
task 1234 approved
git tag -a -m "${task}: $user approved ${task}c1 as ${task}a1." ${task}a1
git tag -l
git push --tags
mail -s '${task}: $user approved ${task}c1 as ${rel}a1.' alice@$site rel@$site
logout

comment "## RelEng merges approved Tasks into rel branch."
ssh dave@dave.dev
cd $rel_dir/$rel/$app
git remote add -f alice $gh/alice/$app
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
./test.sh
git tag -a -m "${rel}: Release Candidate ${rel}c1." ${rel}c1
git tag -l
git push --tags origin
mail -c "${rel}: Release Candiate ${rel}c1 tagged." release@$site
logout

comment "## RelEng merges RC into main head and tags it."
ssh dave@dave.dev
cd $rel_dir/$rel/$app
comment "### RelEng updates master."
git fetch
git checkout master
git pull origin master
comment "### RelEng merges rel candiate ${rel}c1 and tags it into $main master."
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
./test.sh
bash ./foo.sh option > result.out; fgrep -q './foo.sh std' result.out
git log

comment "### Ops pull new tags and checkout ${rel}p1."
git tag -l
git fetch
git tag -l
git checkout ${rel}p1 > result.out 2>&1
fgrep -q "You are in 'detached HEAD' state." result.out
git log

comment "### Ops sanity check."
./test.sh
bash ./foo.sh option > result.out; fgrep -q './foo.sh 1234 option' result.out

comment "### Ops push ${rel}p1 tag."
rake push tag="${rel}p1"
mail -c "${rel}: Released ${rel}p1." production@$site
logout

comment "# Release complete!"

