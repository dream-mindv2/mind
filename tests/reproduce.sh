#!/bin/sh
# Reproducible builds: that `mind attest` signs what a clean build of the last
# commit made, and `mind reproduce` makes the same bytes again -- from another
# clone in another directory, against a standard library somewhere else, and
# for a project's dependency; that a downloaded image is held to the attested
# hash; and that an attestation of other source is skipped and does not pass.
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

fail=0
pass=0

# check NAME WANT_STATUS TEXT -- what the last `mnd` said.
check() {
    case "$out" in
        *"$3"*) if [ "$status" = "$2" ]; then echo "ok   $1"; pass=$((pass + 1)); return; fi ;;
    esac
    echo "FAIL $1: wanted $2 and \"$3\", got $status:"
    echo "$out" | sed 's/^/    /' | head -10
    fail=$((fail + 1))
}

# mnd DIR ARGS -- `mind ARGS` in DIR.
mnd() {
    dir=$1; shift
    out=$(cd "$tmp/$dir" && "$dream" "$mind" "$@" 2>&1)
    status=$?
}

git_c() { git -c user.email=t@t -c user.name=t "$@"; }

mkdir -p "$tmp/keys" && printf '[package]\nname = "k"\nversion = "0.1.0"\n' >"$tmp/keys/mind.toml"
mnd keys keygen --signing-key "$tmp/author.key"
public=$(echo "$out" | tail -1 | tr -d ' ')

# A program with a dependency of its own, so the paths of two packages and
# the standard library all have to be made relative.
mkdir -p "$tmp/greet/src" && (cd "$tmp/greet" && git init -q -b main \
    && printf '[package]\nname = "greet"\nversion = "1.0.0"\n' >mind.toml \
    && echo 'let hello name = "hello, " + name;' >src/words.dr && git add . && git_c commit -qm one && git tag v1)
mkdir -p "$tmp/app/src" && (cd "$tmp/app" && git init -q -b main \
    && printf '[package]\nname = "app"\nversion = "1.2.0"\n\n[dependencies]\ngreet = { git = "file://%s/greet", tag = "v1" }\n' "$tmp" >mind.toml \
    && printf 'import std.console;\nimport greet.words;\nlet main! = console.print! (words.hello "reproducer");\n' >src/main.dr \
    && git add . && git_c commit -qm one)
(cd "$tmp/app" && "$dream" "$mind" deps >/dev/null 2>&1 && git add mind.lock && git_c commit -qm lock)

mnd app attest --release --signing-key "$tmp/author.key"
check "attest builds the last commit and signs it" 0 "attested release v1.2.0 (release): sha256:"
attested=$(sed -n 's/^attested release v1.2.0 (release): //p' <<EOF
$out
EOF
)
(cd "$tmp/app" && "$dream" target/release/app.dream >"$tmp/ran" 2>&1)
case "$(cat "$tmp/ran")" in "hello, reproducer") echo "ok   the attested image runs"; pass=$((pass + 1)) ;;
    *) echo "FAIL the attested image runs: $(cat "$tmp/ran")"; fail=$((fail + 1)) ;; esac
(cd "$tmp/app" && "$dream" "$mind" sign --signing-key "$tmp/author.key" >/dev/null 2>&1 \
    && git add mind.sig && git_c commit -qm attest && git tag v1.2.0)

# Somebody else: another clone, in another directory.
git clone -q "$tmp/app" "$tmp/elsewhere/deeper/app"
mnd elsewhere/deeper/app reproduce --release
check "another clone elsewhere makes the same bytes" 0 "reproduced v1.2.0 (release)"
check "and says so" 0 "1 reproduced, 0 differ, 0 skipped"

# The standard library somewhere else entirely: its paths are made relative too.
mkdir -p "$tmp/stdcopy" && cp -R "$root/mind/std" "$tmp/stdcopy/std"
out=$(cd "$tmp/elsewhere/deeper/app" && MIND_STDLIB="$tmp/stdcopy" "$dream" "$mind" reproduce --release 2>&1); status=$?
check "a standard library in another place makes the same bytes" 0 "1 reproduced"

cp "$tmp/app/target/release/app.dream" "$tmp/download.dream"
mnd elsewhere/deeper/app reproduce --release --image "$tmp/download.dream"
check "a downloaded image is the attested one" 0 "the image given is it"
printf 'x' >>"$tmp/download.dream"
mnd elsewhere/deeper/app reproduce --release --image "$tmp/download.dream"
check "a tampered download is not" 1 "the image given is NOT it"

(cd "$tmp/elsewhere/deeper/app" && echo '// changed' >>src/main.dr && git_c commit -qam changed)
mnd elsewhere/deeper/app reproduce --release
check "an attestation of other source is skipped, and nothing passes" 1 "attests other source"

# A dependency: the user, who trusts the author's key, rebuilds what they
# fetched against the author's attestation. One by a key they do not trust
# would be listed and ignored.
mkdir -p "$tmp/user/src" && printf '[package]\nname = "user"\nversion = "0.1.0"\n\n[dependencies]\napp = { git = "file://%s/app", tag = "v1.2.0", keys = ["%s"] }\n' "$tmp" "$public" >"$tmp/user/mind.toml"
echo 'let main! = ();' >"$tmp/user/src/main.dr"
mnd user reproduce app --release
check "a dependency is reproduced from what was fetched" 0 "reproduced v1.2.0 (release)"

case "$attested" in sha256:*) ;; *) echo "FAIL the attested hash was not read: $attested"; fail=$((fail + 1)) ;; esac

echo
echo "$pass reproduce cases passed, $fail failed"
[ "$fail" -eq 0 ]
