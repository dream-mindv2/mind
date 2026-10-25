#!/bin/sh
# Real builds installed from the current package, a directory and Git,
# including GitHub shorthand via an offline URL rewrite.
set -eu
dream=${dream:-build-dream/bin/dream}
mind=${mind:-build/mind}
dreams=${dreams:-dreams/bootstrap/dreams.dream}
root=$(pwd)
case "$dream" in /*) ;; *) dream="$root/$dream" ;; esac
case "$mind" in /*) ;; *) mind="$root/$mind" ;; esac
case "$dreams" in /*) ;; *) dreams="$root/$dreams" ;; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/temp" "$tmp/outside" "$tmp/work/current" "$tmp/work/addon" "$tmp/work/helper" "$tmp/repos/app.git"
export DREAM="$dream" DREAMS="$dreams" MIND_STDLIB="$root/mind" MIND_HOME="$tmp/home"
export MINDV2_PATH="$tmp/installed tools" TMPDIR="$tmp/temp"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://$tmp/repos/.insteadOf" GIT_CONFIG_VALUE_0="https://github.com/fixture/"
passed=0

run() {
    where=$1; shift
    status=0
    out=$(cd "$where" && timeout 90 "$dream" "$mind" "$@" 2>&1) || status=$?
}
check() {
    if [ "$status" != "$1" ]; then printf 'FAIL %s: status %s, expected %s\n%s\n' "$2" "$status" "$1" "$out"; exit 1; fi
    printf 'ok   %s\n' "$2"
    passed=$((passed + 1))
    if [ -n "$(ls -A "$tmp/temp")" ]; then echo 'FAIL temporary build directory leaked'; exit 1; fi
}
image() {
    got=$(cd "$tmp/outside" && "$dream" -x "$1")
    if [ "$got" != "$2" ]; then printf 'FAIL dream -x %s: expected %s, got %s\n' "$1" "$2" "$got"; exit 1; fi
}

printf '[package]\nname = "current"\nlicense = "MIT"\n' >"$tmp/work/current/mind.toml"
printf 'import std.console;\nlet main! = console.print! "current";\n' >"$tmp/work/current/main.dr"
run "$tmp/work/current" install
check 0 'bare install builds and installs the current package'
test -f "$tmp/work/current/target/debug/current.dream"
image current current

printf '[package]\nname = "helper"\nlicense = "MIT"\n' >"$tmp/work/helper/mind.toml"
printf 'let word = "helper";\n' >"$tmp/work/helper/lib.dr"
cat >"$tmp/work/addon/mind.toml" <<'EOF'
[package]
name = "addon"
license = "MIT"
[build]
output = "must-not-be-created.dream"
[dependencies]
helper = "../helper"
EOF
cat >"$tmp/work/addon/build.dr" <<'EOF'
import std.build;
let plan ctx = build.empty |> build.module "generated" (build.write "generated.dr" "let word = \"generated\";");
EOF
cat >"$tmp/work/addon/main.dr" <<'EOF'
import std.console;
import helper.lib;
import addon.generated;
when release { let mode = "release"; }
when not release { let mode = "debug"; }
let main! = console.print! (lib.word + " " + generated.word + " " + mode);
EOF
printf '' >"$tmp/work/addon/mind.lock"
run "$tmp/outside" install ../work/addon --name addon-tool --release
check 0 'directory installs build scripts and relative dependencies in temporary output'
image addon-tool 'helper generated release'
test ! -e "$tmp/work/addon/target"
test ! -e "$tmp/work/addon/must-not-be-created.dream"
test ! -s "$tmp/work/addon/mind.lock"
test ! -e "$tmp/work/helper/target"
test ! -e "$tmp/work/helper/mind.lock"

before=$(cksum "$MINDV2_PATH/addon-tool.dream")
printf 'let main! = ;\n' >"$tmp/work/addon/main.dr"
run "$tmp/outside" install ../work/addon --name addon-tool
check 1 'a failed directory build preserves the installed image and cleans temporary files'
test "$(cksum "$MINDV2_PATH/addon-tool.dream")" = "$before"
image addon-tool 'helper generated release'

repo="$tmp/repos/app.git"
git init -q -b main "$repo"
printf '[package]\nname = "remote"\nlicense = "MIT"\n' >"$repo/mind.toml"
printf 'import std.console;\nlet main! = console.print! "first";\n' >"$repo/main.dr"
git -C "$repo" add .
git -C "$repo" -c user.email=test@example.com -c user.name=test commit -qm first
git -C "$repo" tag v1
revision=$(git -C "$repo" rev-parse HEAD)
printf 'import std.console;\nlet main! = console.print! "latest";\n' >"$repo/main.dr"
git -C "$repo" -c user.email=test@example.com -c user.name=test commit -qam latest

run "$tmp/outside" install "file://$repo"
check 0 'a Git URL without a pin installs the default branch'
image remote latest
run "$tmp/outside" install github:fixture/app#v1 --name from-tag
check 0 'GitHub shorthand and #tag select the requested release'
image from-tag first
run "$tmp/outside" install github:fixture/app --rev "$revision" --name from-rev
check 0 'a revision installs the requested commit'
image from-rev first
run "$tmp/outside" install github:fixture/app --branch main --name from-branch
check 0 'a branch selects its current checkout'
image from-branch latest
run "$tmp/outside" install github:fixture/app --tag v1 --name from-tag-option
check 0 'the tag option selects the requested release'
image from-tag-option first

printf 'import std.console;\nlet main! = console.print! "newer";\n' >"$repo/main.dr"
git -C "$repo" -c user.email=test@example.com -c user.name=test commit -qam newer
run "$tmp/outside" install github:fixture/app
check 0 'install fetches fresh source rather than reusing an old branch checkout'
image remote newer
test ! -e "$repo/target"
test ! -e "$repo/mind.lock"

cp "$MINDV2_PATH/current.dream" "$MINDV2_PATH/current"
printf 'import std.console;\nlet main! = console.print! "upgraded";\n' >"$tmp/work/current/main.dr"
run "$tmp/work/current" install
check 0 'reinstall replaces a bare image that would otherwise shadow the .dream file'
image current upgraded

run "$tmp/outside" install github:fixture
check 1 'malformed GitHub shorthand is reported'
run "$tmp/outside" install ../work/current --name ../escape
check 1 'an installed name cannot escape the installation directory'
run "$tmp/outside" install ../work/missing
check 1 'a missing source is reported and cleaned up'
run "$tmp/outside" install github:fixture/missing
check 1 'a failed Git clone is reported and cleaned up'
run "$tmp/outside" install ../work/current --output "$tmp/no.dream"
check 1 'explicit source installs require temporary output'
test ! -e "$tmp/no.dream"
run "$tmp/outside" install ../work/current ../work/helper
check 1 'more than one source is rejected'
run "$tmp/outside" install
check 1 'bare install outside a project reports the missing project'
run "$tmp/outside" install github:fixture/app --name remote --key ed25519:0000000000000000000000000000000000000000000000000000000000000000
check 1 'a requested signing key is enforced before installation'
image remote newer

printf '\n%s install cases passed\n' "$passed"
