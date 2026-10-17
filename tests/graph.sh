#!/bin/sh
# The dependency graph, against packages on disk: cycles, diamonds, version
# requirements, build dependencies in their own namespace, two revisions of
# one repository, the lock, the hashes and mirrors it pins, and signed
# releases. Each case is a directory of manifests, one
# `mind deps`, and the first line of what it said.
set -u

dream=${dream:-build-dream/bin/dream}
mind=${mind:-build/mind}
root=$(pwd)
# Absolute, since each case runs from inside its own project.
case "$dream" in /*) ;; *) dream="$root/$dream" ;; esac
case "$mind" in /*) ;; *) mind="$root/$mind" ;; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MIND_STDLIB="$root/mind" MIND_HOME="$tmp/home"

fail=0
pass=0

# pkg DIR VERSION EXTRA -- a package with one module and a manifest.
pkg() {
    mkdir -p "$tmp/$1/src"
    printf '[package]\nname = "%s"\nversion = "%s"\n%b' "$(basename "$1")" "$2" "$3" >"$tmp/$1/mind.toml"
    echo 'let x = 1;' >"$tmp/$1/src/lib.dr"
}

# check NAME CASE STATUS TEXT [COMMAND] -- run `mind COMMAND` in CASE/app.
check() {
    name=$1; dir=$2; want_status=$3; want=$4; cmd=${5:-deps}
    out=$(cd "$tmp/$dir/app" && "$dream" "$mind" $cmd 2>&1)
    got_status=$?
    case "$out" in
        *"$want"*) if [ "$got_status" = "$want_status" ]; then
                       echo "ok   $name"; pass=$((pass + 1)); return
                   fi ;;
    esac
    echo "FAIL $name: wanted $want_status and \"$want\", got $got_status:"
    echo "$out" | sed 's/^/    /' | head -8
    fail=$((fail + 1))
}

pkg cyc/app 0.1.0 '[dependencies]\na = "../a"\n'
pkg cyc/a 1.0.0 '[dependencies]\napp = "../app"\n'
check "a cycle is refused" cyc 1 "  a    uses  app  (../a/mind.toml)"

pkg bcyc/app 0.1.0 '[dependencies]\nsqlite = "../sqlite"\n'
pkg bcyc/sqlite 3.0.0 '[build-dependencies]\ncodegen = "../codegen"\n'
pkg bcyc/codegen 1.0.0 '[dependencies]\napp = "../app"\n'
check "a cycle through a build script is refused" bcyc 1 "sqlite   builds with  codegen"

pkg dia/app 0.1.0 '[dependencies]\na = "../a"\nb = { path = "../b", version = "^2" }\n'
pkg dia/a 1.0.0 '[dependencies]\nc = { path = "../c", version = "^1.2" }\n'
pkg dia/b 2.1.0 '[dependencies]\nc = { path = "../c", version = ">=1.4, <2" }\n'
pkg dia/c 1.5.0 ''
check "a diamond whose requirements agree is one package" dia 0 "  c v1.5.0"

pkg miss/app 0.1.0 '[dependencies]\na = "../a"\nc = { path = "../c", version = "^1.6" }\n'
pkg miss/a 1.0.0 '[dependencies]\nc = { path = "../c", version = "^1.2" }\n'
pkg miss/c 1.5.0 ''
check "a version nobody accepts names every requirement" miss 1 "(mind.toml)  <- not 1.5.0"

pkg inc/app 0.1.0 '[dependencies]\na = "../a"\nc = { path = "../c", version = "^2" }\n'
pkg inc/a 1.0.0 '[dependencies]\nc = { path = "../c", version = "^1.2" }\n'
pkg inc/c 1.5.0 ''
check "requirements no version meets are said to be" inc 1 "no version meets all of these"

pkg bare/app 0.1.0 '[dependencies]\nc = { path = "../c", version = "^1" }\n'
mkdir -p "$tmp/bare/c"
check "a bare directory has no version to require" bare 1 "has no manifest, so it has no version"

pkg badreq/app 0.1.0 '[dependencies]\nc = { path = "../c", version = "^one" }\n'
pkg badreq/c 1.0.0 ''
check "a requirement that is not one is reported" badreq 1 "is not one: \`^one\`"

pkg ns/app 0.1.0 '[dependencies]\njson = { path = "../json2", version = "^2" }\n[build-dependencies]\njson = { path = "../json1", version = "^1" }\n'
pkg ns/json1 1.0.0 ''
pkg ns/json2 2.0.0 ''
check "a build script's packages are a namespace of their own" ns 0 "[build: this project]"
check "the tree shows them under [build]" ns 0 "  [build]" tree

# Git, over file://, for the two cases only a repository can make.
mkdir -p "$tmp/repo"
(cd "$tmp/repo" && git init -q && printf '[package]\nname = "json"\nversion = "1.0.0"\n' >mind.toml \
    && echo 'let v = 1;' >lib.dr && git add . && git -c user.email=t@t -c user.name=t commit -qm one \
    && git tag v1.0 && echo 'let w = 2;' >>lib.dr \
    && git -c user.email=t@t -c user.name=t commit -qam two && git tag v1.1)
url="file://$tmp/repo"

pkg rev/app 0.1.0 "[dependencies]\na = \"../a\"\njson = \"$url#v1.1\"\n"
pkg rev/a 1.0.0 "[dependencies]\njson = \"$url#v1.0\"\n"
check "two revisions of one repository are said to be" rev 1 "two revisions of \`json\`"

pkg lock/app 0.1.0 "[dependencies]\njson = \"$url#v1.0\"\n"
check "a resolved graph is locked" lock 0 "json v1.0.0"
(cd "$tmp/repo" && echo 'let z = 3;' >>lib.dr && git -c user.email=t@t -c user.name=t commit -qam three \
    && git tag -f v1.0 >/dev/null)
rm -rf "$tmp/home/cache"
check "a moved tag disagrees with the lock" lock 1 "has commit "
check "update accepts it" lock 0 "updated json" update
check "and the lock agrees again" lock 0 "json v1.0.0"

# The bytes, not the URL. The lock holds what the fetched copy hashes to;
# `verify` holds the cache to it; a mirror serves the locked bytes when the
# source is gone, and is refused when it serves anything else.
has() {
    if grep -q "$2" "$3"; then echo "ok   $1"; pass=$((pass + 1))
    else echo "FAIL $1: no \"$2\" in $3"; sed 's/^/    /' "$3"; fail=$((fail + 1)); fi
}
has "the lock records what the bytes hash to" 'hash = "sha256:' "$tmp/lock/app/mind.lock"
check "verify agrees with an untouched cache" lock 0 "verified 1 fetched packages" verify
echo 'let planted = 1;' >>"$(ls -d "$tmp"/home/cache/*repo*)/lib.dr"
check "a build trusts the hash it kept" lock 0 "json v1.0.0"
check "verify does not" lock 1 "are not what was fetched" verify
check "update fetches it again" lock 0 "updated json" update
check "and verify agrees" lock 0 "verified 1" verify
check "a mirror is written" lock 0 "wrote 1 packages" "mirror $tmp/mirror"
check "and not twice" lock 0 "(1 already there)" "mirror $tmp/mirror"
mv "$tmp/repo" "$tmp/repo.gone"
rm -rf "$tmp/home/cache"
check "a source that is gone, with no mirror, is an error" lock 1 "none is configured"
export MIND_MIRRORS="$tmp/mirror"
check "a mirror serves the locked bytes" lock 0 "json v1.0.0"
check "and they verify" lock 0 "verified 1" verify
has "the commit survives the trip" 'commit = "' "$tmp/lock/app/mind.lock"
archive=$(ls "$tmp"/mirror/*.tar.gz)
mkdir -p "$tmp/evil" && echo 'let evil = 1;' >"$tmp/evil/lib.dr" && tar -czf "$archive" -C "$tmp/evil" .
rm -rf "$tmp/home/cache"
check "a mirror that serves anything else is refused" lock 1 "served different contents"
unset MIND_MIRRORS
mv "$tmp/repo.gone" "$tmp/repo"

# A tarball replaced behind the same URL has no commit to move: only its
# hash says it changed.
mkdir -p "$tmp/tgz/pkg" && printf '[package]\nname = "tz"\nversion = "1.0.0"\n' >"$tmp/tgz/pkg/mind.toml"
echo 'let v = 1;' >"$tmp/tgz/pkg/lib.dr" && tar -czf "$tmp/tz.tar.gz" -C "$tmp/tgz" pkg
pkg tgz/app 0.1.0 "[dependencies]\ntz = \"file://$tmp/tz.tar.gz\"\n"
check "a tarball is locked by its bytes" tgz 0 "tz v1.0.0"
echo 'let v = 2;' >"$tmp/tgz/pkg/lib.dr" && tar -czf "$tmp/tz.tar.gz" -C "$tmp/tgz" pkg
rm -rf "$tmp/home/cache"
check "a replaced tarball disagrees with the lock" tgz 1 "has contents sha256:"

# Signed releases. An author makes a key and signs a commit; a user who
# trusts the key gets that release, and nothing else is let through -- an
# unsigned one, another key's, or a commit made after the signature.
git_c() { git -c user.email=t@t -c user.name=t "$@"; }
author="$tmp/author.key"
mkdir -p "$tmp/keyapp" && printf '[package]\nname = "k"\nversion = "0.1.0"\n' >"$tmp/keyapp/mind.toml"
public=$(cd "$tmp/keyapp" && "$dream" "$mind" keygen --signing-key "$author" | tail -1 | tr -d ' ')
case "$(stat -c %a "$author" 2>/dev/null || stat -f %Lp "$author")" in
    600) echo "ok   a signing key is readable by its owner alone"; pass=$((pass + 1)) ;;
    *) echo "FAIL a signing key is readable by its owner alone"; fail=$((fail + 1)) ;;
esac
other=$(cd "$tmp/keyapp" && "$dream" "$mind" keygen --signing-key "$tmp/other.key" | tail -1 | tr -d ' ')
out=$(cd "$tmp/keyapp" && "$dream" "$mind" keygen --signing-key "$author" 2>&1)
case "$out" in *"already holds a key"*) echo "ok   a key is never replaced"; pass=$((pass + 1)) ;;
    *) echo "FAIL a key is never replaced: $out"; fail=$((fail + 1)) ;; esac

mkdir -p "$tmp/srepo" && (cd "$tmp/srepo" && git init -q && printf '[package]\nname = "signed"\nversion = "1.0.0"\n' >mind.toml \
    && echo 'let v = 1;' >lib.dr && git add . && git_c commit -qm one)
(cd "$tmp/srepo" && "$dream" "$mind" sign --signing-key "$author" >/dev/null && git add mind.sig \
    && git_c commit -qm sign && git tag v1 \
    && echo 'let w = 2;' >>lib.dr && git_c commit -qam unsigned && git tag v2 \
    && git rm -q mind.sig && git_c commit -qm nosig && git tag v3)
surl="file://$tmp/srepo"

pkg sig/app 0.1.0 "[dependencies]\ns = { git = \"$surl\", tag = \"v1\", keys = [\"$public\"] }\n"
check "a release signed by a trusted key is used" sig 0 "s v1.0.0 (package"
check "and verify says so" sig 0 "1 of them signed by a key they trust" verify
pkg wrong/app 0.1.0 "[dependencies]\ns = { git = \"$surl\", tag = \"v1\", keys = [\"$other\"] }\n"
check "a release signed by another key is refused" wrong 1 "is not signed by a key its entry trusts"
pkg moved/app 0.1.0 "[dependencies]\ns = { git = \"$surl\", tag = \"v2\", keys = [\"$public\"] }\n"
check "a commit after the signature is refused" moved 1 "but what arrived hashes to"
pkg bare/app 0.1.0 "[dependencies]\ns = { git = \"$surl\", tag = \"v3\", keys = [\"$public\"] }\n"
check "an unsigned release is refused" bare 1 "has no mind.sig"
pkg plain/app 0.1.0 "[dependencies]\ns = { git = \"$surl\", tag = \"v3\" }\n"
check "a dependency that names no key needs no signature" plain 0 "s v1.0.0 (package"
pkg added/app 0.1.0 ""
check "add --key trusts the key" added 0 "added signed" "add $surl --tag v1 --key $public"
has "and writes it into the manifest" "keys = \[\"$public\"\]" "$tmp/added/app/mind.toml"
check "add --key refuses a release the key did not sign" added 1 "but what arrived hashes to" "add $surl --tag v2 --name s2 --key $public"
check "a signed release goes into a mirror" sig 0 "wrote 1 packages" "mirror $tmp/smirror"
mv "$tmp/srepo" "$tmp/srepo.gone"
rm -rf "$tmp/home/cache"
export MIND_MIRRORS="$tmp/smirror"
check "and comes back out of it still signed" sig 0 "1 of them signed by a key they trust" verify
unset MIND_MIRRORS
mv "$tmp/srepo.gone" "$tmp/srepo"

echo
echo "$pass graph cases passed, $fail failed"
[ "$fail" -eq 0 ]
