#!/bin/sh
# `mind release`: that it moves the version in mind.toml and every
# `[release] files` entry together, runs `[release] run` between that and the
# commit, commits, signs, tags and pushes -- a new file included -- and that it
# refuses a dirty tree, a source whose version disagrees with the manifest, a
# version not newer than the last, and a tag already taken. Pushed to a bare
# repository here, and never published.
set -u

dream=${dream:-build-dream/bin/dream}
mind=${mind:-build/mind}
dreams=${dreams:-build/dreams.dream}
root=$(pwd)
case "$dream" in /*) ;; *) dream="$root/$dream" ;; esac
case "$mind" in /*) ;; *) mind="$root/$mind" ;; esac
case "$dreams" in /*) ;; *) dreams="$root/$dreams" ;; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MIND_STDLIB="$root/mind" MIND_HOME="$tmp/home" DREAM="$dream" DREAMS="$dreams"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

fail=0
pass=0

check() {
    case "$out" in
        *"$3"*) if [ "$status" = "$2" ]; then echo "ok   $1"; pass=$((pass + 1)); return; fi ;;
    esac
    echo "FAIL $1: wanted $2 and \"$3\", got $status:"
    echo "$out" | sed 's/^/    /' | head -10
    fail=$((fail + 1))
}
mnd() { out=$(cd "$tmp/pkg" && timeout 120 "$dream" "$mind" "$@" --signing-key "$tmp/key" 2>&1); status=$?; }
in_pkg() { (cd "$tmp/pkg" && "$@"); }

mkdir -p "$tmp/keys" && printf '[package]\nname = "k"\nversion = "0.1.0"\nlicense = "MIT"\n' >"$tmp/keys/mind.toml"
(cd "$tmp/keys" && "$dream" "$mind" keygen --signing-key "$tmp/key" >/dev/null 2>&1)

git init -q --bare "$tmp/origin.git"
mkdir -p "$tmp/pkg/src"
printf '[package]\nname = "relpkg"\nversion = "1.2.3"\nlicense = "MIT"\n\n[release]\nfiles = ["src/main.dr"]\nrun = ["echo made > made.txt"]\n' >"$tmp/pkg/mind.toml"
printf 'let version = "1.2.3";\nlet main! = ();\n' >"$tmp/pkg/src/main.dr"
in_pkg git init -q -b main && in_pkg git add -A && in_pkg git commit -qm init
in_pkg git remote add origin "$tmp/origin.git" && in_pkg git push -q origin main

mnd release --dry-run
check "a dry run says each step and does none" 0 "would push the branch and v1.2.4"
[ "$(in_pkg git log --oneline | wc -l)" = 1 ] || { echo "FAIL the dry run committed"; fail=$((fail + 1)); }

touch "$tmp/pkg/stray"
mnd release --no-publish
check "a dirty tree is refused" 1 "commit or stash what is changed first"
rm "$tmp/pkg/stray"

sed 's/1.2.3/1.2.2/' "$tmp/pkg/src/main.dr" >"$tmp/m" && mv "$tmp/m" "$tmp/pkg/src/main.dr"
in_pkg git commit -qam drift
mnd release --no-publish
check "a source that disagrees with the manifest is refused" 1 "says 1.2.2 and mind.toml 1.2.3"
in_pkg git reset -q --hard HEAD~1

mnd release 1.0.0 --no-publish
check "a version not newer than the last is refused" 1 "must be newer than 1.2.3"

mnd release minor --no-publish
check "a release moves the version, commits, signs, tags and pushes" 0 "push the branch and v1.3.0"
grep -q 'version = "1.3.0"' "$tmp/pkg/mind.toml" && grep -q 'let version = "1.3.0";' "$tmp/pkg/src/main.dr" \
    && echo "ok   the manifest and the listed source both say 1.3.0" && pass=$((pass + 1)) \
    || { echo "FAIL the version did not move in both"; fail=$((fail + 1)); }
[ "$(git -C "$tmp/origin.git" tag)" = "v1.3.0" ] && git -C "$tmp/origin.git" show --stat v1.3.0~1 | grep -q made.txt \
    && echo "ok   the tag is pushed, and the release commit has what [release] run made" && pass=$((pass + 1)) \
    || { echo "FAIL the tag or the made file is missing upstream"; fail=$((fail + 1)); }
[ -z "$(in_pkg git status --porcelain)" ] && echo "ok   the tree is clean after" && pass=$((pass + 1)) \
    || { echo "FAIL the tree is dirty after a release"; fail=$((fail + 1)); }

in_pkg git tag v1.3.1
mnd release --no-publish
check "a tag already taken is refused" 1 "v1.3.1 is already a tag here"

echo "$pass release cases passed, $fail failed"
[ "$fail" = 0 ]
