# mind

**The build tool for [Dream](https://github.com/dream-mindv2/dream)**, a lazily
evaluated functional language. `mind` is to `dreams` what Cargo is to `rustc`:
it reads a manifest, finds and fetches the packages a project needs, runs
their build scripts, hands the lot to the compiler, and then runs, tests,
documents and packages what it made. It is written in Dream.

```sh
mind new hello && cd hello
mind run                        # Hello from hello
```

- **Dependencies are one line.** A directory, a pinned git URL or a tarball,
  under the name you import it by. No registry and no lock-step versions.
  `mind.lock` records what was resolved, and drift stops the build.
- **Builds are cached to the module.** Dream compiles whole programs, so there
  is no link step. What is kept between builds is each module's parse,
  resolution, lowering and type check, so an edit recompiles the module it
  touched and reads the rest back.
- **Build scripts are pure Dream.** `build.dr` returns a plan: generated
  modules, embedded files, C and C++ libraries built with GCC, Clang, MSVC or
  CMake, each step cached by what it read.
- **`mind test` runs everything at once**: every package's unit tests and every
  check its build script declares.
- **`mind docs` writes a documentation site** from Markdown guides and `///`
  comments. It runs every example and shows its output, links every name in
  code to its reference, the standard library's included, and works offline.
  `mind docs serve --watch` serves it and rebuilds as you write.
- **`mind serve DIR`** serves a directory over HTTP on 127.0.0.1, with the
  limits a server left running needs.
- **`mind pack`** makes `.deb`, `.rpm` and Arch packages, Homebrew formulas,
  tarballs and install scripts, every byte written in Dream.

## Installing

`mind` comes with Dream. The quickest way is a released toolchain:

```sh
curl -fsSL https://dream-mindv2.github.io/toolchain/install.sh | sh
```

which installs the latest release of the whole language, checked, into
`~/.mindv2/toolchains/VERSION`, and links `dream` and `mind` into
`~/.local/bin` -- adding that to `PATH` only where it is not already. After that `mind`
manages them (see "Toolchains" below). Or build and install from the
[workspace](https://github.com/Custards1/dream):

```sh
git clone --recursive https://github.com/Custards1/dream
cd dream
./build.sh                      # the VM; says what is missing if anything is
just install                    # dream, mind, the compiler and std, in ~/.mindv2
```

`mind` needs the VM (`dream`), the compiler (`dreams.dream`) and the standard
library, and finds all three in the installation by itself.

## Toolchains

A toolchain is one release of the whole language -- VM, compiler, `mind`,
language server and standard library -- from
[dream-mindv2/toolchain](https://github.com/dream-mindv2/toolchain). Several
can be installed side by side, one in use:

```sh
mind toolchain list                # installed, and which is in use
mind toolchain list --available    # every release
mind toolchain install [VERSION]   # the latest, or VERSION, beside the others
mind toolchain use VERSION         # switch (back down, too), installing it if need be
mind toolchain update              # the latest, and use it
mind toolchain remove VERSION
mind toolchain which
```

Each lives in `~/.mindv2/toolchains/VERSION` (`$MINDV2_HOME`), and
`~/.mindv2/current` links to the one in use, whose `bin` is on `PATH`. A
project pins the toolchain it builds with in `mind.toml`:

```toml
[toolchain]
version = "0.3.0"
```

and `mind` run there hands the command to that toolchain, installing it first
if it is not here. A `mind` built from source has no toolchain of its own and
leaves pins alone. Every toolchain is checked against its release's
`SHA256SUMS` and a signature of them by a key `mind` was built trusting before
anything is unpacked; on a Linux without the usual dynamic loader (NixOS
without nix-ld, Guix) its VM is run through the system's own loader.
[src/toolchain.dr](src/toolchain.dr) is the design.

## A project

```
mind new hello                  # hello/mind.toml and hello/src/main.dr
cd hello                        # or, in a directory that exists: mind init
mind run                        # build target/debug/hello.dream and run it
mind add ../util                # depend on a directory
mind test                       # every test, at once
```

```toml
# mind.toml
[package]
name = "hello"
version = "0.1.0"

[dependencies]
util = "../util"

[vm]                            # optional: asked of the VM that runs it
nursery_max = "64M"
```

`[vm]` is what a program asks of the VM that runs it, and only the root
package's counts -- a library has no say in how the program using it runs.
The compiler writes it into the image, so it holds however the image is run;
`dream --nursery-max` and `DREAM_NURSERY_MAX` still overrule it. One setting
so far: `nursery_max`, the most a process's nursery may grow to, as bytes or a
size such as `"64M"` (the VM's default is 32 MB). A key it does not know is an
error in the manifest.

`[payload]` lists files the program carries in its image, each under the
name it is found by, as paths relative to the manifest:

```toml
[payload]
logo = "assets/logo.png"
schema = "sql/schema.sql"
```

`payload.named "logo"` (`std.payload`) answers the bytes where the image
lies, and `payload.text "schema"` a copy as an ordinary string, for a small
file. A dependency's payloads go into every program that uses it, since its
code reads them; two packages naming two different files the same is an error,
as is a name with `/` or `=` in it. It is the compiler's `--payload NAME=FILE`
written down once, and a build script's `build.payload` is the same for a file
that has to be made first.

**A release build carries the licences** of its package and of every
dependency: each licence file at a package's root (`LICENSE`, `LICENSE-MIT`,
`COPYING`, `NOTICE`, ..) gathered into one payload, `licenses`, each under a
line naming the package and the file, so a program's `--licenses` prints
`payload.licenses ()`. A licence such as MIT's asks that its text go wherever
the software does, and a program is one file. A debug build carries none, and
`licenses = false` in `[profile.release]` (or in `[build]`, for every
profile) leaves them out:

```toml
[profile.release]
licenses = false
```

**A release build checks the licences** of its dependencies against its own
`[package] license`, an SPDX expression (`MIT OR Apache-2.0`), and fails if
one does not allow it: a GPL library in an MIT program, Apache-2.0 in a
GPL-2.0-only one, a dependency that declares no licence (which may not be
redistributed at all), or one the check does not know. A dependency's `A OR
B` is taken as whichever fits; the package's own `A OR B` must be allowed in
full. LGPL counts as GPL, since one Dream image cannot be relinked in part.
It is a cautious reading, not legal advice, and the author decides:
`--no-license-check`, or `license-check = false` in `[profile.release]` (or
`[build]`), builds anyway, and `[licenses] accept = ["LicenseRef-Acme"]`
takes a licence it does not know as permissive. src/licenses.dr has the
rules.

Every command but `new` and `init` looks for `mind.toml` here or above, so
they work from anywhere inside a project, the way `git` finds its root.
`-C DIR` runs `mind` as if it had been started in DIR, as `git -C` and
`make -C` do: the project is found from there, and every relative path on the
line (`-o`, `-L`, what `mind add` is given) means what it would typed there.
Given twice, the second is relative to the first.

## Commands

| | |
|---|---|
| `mind new NAME` | create a project in `./NAME` |
| `mind init [NAME]` | make this directory a project, named after it unless NAME is given; a `main.dr` or `src/` already there is kept |
| `mind build` | compile to `target/<profile>/<name>.dream`; an application, to `target/<profile>/<name>/` ([Applications](#applications)) |
| `mind build GOAL..` | make what the build script names instead ([Goals](#goals)) |
| `mind install [SOURCE]` | build and install the current package, a directory, Git URL, or `github:USER/REPO` for `dream -x NAME` |
| `mind run [-- args]` | compile, then run with the arguments given; an application is served on 127.0.0.1, or opened in a window with `--desktop` |
| `mind run FILE.dr [args]` | compile and run one file on its own, with the standard library and the modules beside it; no project needed |
| `mind test [NAME..]` | run every test at once: each package's units and its build script's checks |
| `mind check` | compile without writing an image |
| `mind repl` | deprecated interactive session; use source files with `mind run` |
| `mind add SOURCE` | add a dependency: a directory, a git URL, or a tarball |
| `mind remove NAME` | take one out again |
| `mind fetch` | download dependencies without building |
| `mind update [NAME]` | fetch git and URL dependencies again; `--allow-downgrade` takes an older version |
| `mind verify` | hash every fetched dependency again and hold it to `mind.lock` |
| `mind mirror DIR` | write every fetched dependency into `DIR`, as a mirror serves it |
| `mind keygen` | make a key to sign releases with, and print its public half |
| `mind sign [RELEASE]` | sign this package's last commit as `RELEASE` into `mind.sig` |
| `mind rotate ed25519:NEW` | hand this key's trust to another |
| `mind revoke [CERT]` | publish this key's revocation in `mind.sig` |
| `mind attest [RELEASE]` | build the last commit reproducibly and sign what went in and came out |
| `mind reproduce [DEP]` | rebuild what the attestations describe and compare; `--image FILE` checks a download |
| `mind publish [RELEASE]` | submit this package's signed release to the index |
| `mind search [TEXT]` | the packages the indexes have whose names hold `TEXT` |
| `mind audit` | every fetched dependency checked for releases yanked and keys revoked since |
| `mind index VERB` | keep an index: `init`, `admit`, `transfer`, `rotate`, `yank`, `keepers`, `checkpoint`, `cosign`, `submit`, `append`, `verify` |
| `mind deps`, `mind tree` | every package the project resolves to, as a list or as who needs what |
| `mind info` | what this build would run, without running it |
| `mind options` | every package's options, and what this build sets them to |
| `mind pack FORMAT` | create release packages ([Packaging](PACKAGING.md)) |
| `mind docs` | compile guides and API comments, including example output ([Documentation](DOCUMENTATION.md)) |
| `mind docs serve [--watch]` | build the documentation and serve it on 127.0.0.1, rebuilding as sources change |
| `mind serve [DIR]` | serve a directory over HTTP on 127.0.0.1 ([Serving](DOCUMENTATION.md#serving)) |
| `mind clean` | remove `target/` |

`mind help` lists the flags. The ones a build takes are the compiler's
(`-L`, `-D`, `--target`, `--release`), plus `--profile`, `--compiler`,
`-j` and `-f ARG` to pass anything else through as written.

`mind build --precompile` is the one option that is the VM's rather than the
compiler's: it hands `--precompile` to the VM that runs `dreams`, so every
function the JIT can take is compiled before the build starts.

`mind install` builds the current package with the usual build settings and
installs `<name>.dream` in `path.dream_dir! ()`, the first directory used by
`dream -x` (`MINDV2_PATH`, the VM's packaged installation, or `~/.mindv2`).
Use `--release` or `--profile NAME` to choose a different profile, and
`--name NAME` to choose the installed program's name:

```sh
mind install
mind install ../my-tool --release
mind install https://github.com/user/tool.git
mind install github:user/tool --name my-tool
mind install github:user/tool#v1.0
mind install github:user/tool --branch main
dream -x my-tool
```

An unpinned Git source takes the default branch's current HEAD; `#REF`,
`--tag`, `--branch`, and `--rev` select a revision. Each remote install gets
a fresh checkout, and `--key` checks a source's signature as it does for a
dependency. Dependencies still require their ordinary pins and lock checks.
An explicit source builds its image, generated modules, and script drivers
in a temporary directory, cleaned up on success or failure. Local sources
and relative dependencies are read in place; their lockfiles are read but
not rewritten. A manifest's output path is ignored for these temporary
builds; `--output` is available for bare `mind install` only.

Installing again replaces the previous image after a successful build, by
rename. A failed build leaves the installed image intact. Existing bare
images are replaced at their original spelling so they cannot shadow a new
`.dream` image.

## Dependencies

**Listing a dependency is the whole of using it.** Nothing else goes in the
manifest to make one importable:

```toml
[dependencies]
util  = "../util"                                   # a directory
json  = "https://github.com/u/dream-json#v1.0"      # git, pinned after the #
http  = { git = "https://github.com/u/http", branch = "main" }
quiet = "https://example.com/quiet-1.0.tar.gz"      # a tarball

[dev-dependencies]                                  # only `mind test` sees these
bench = "../bench"
```

then `import util.strings`, `import json.parse`. Or let `mind` write the line,
which it does without disturbing the rest of the file:

```
mind add ../util
mind add https://github.com/u/dream-json --tag v1.0
mind add --dev ../bench
mind remove bench
```

- **The key is the import name.** `json = ..` is imported as `json`, whatever
  the package calls itself, so a repository named `dream-json` is still `json`
  to you. (`-L json=DIR` is how the compiler is told.)
- **A bare string is a source.** A path, or a URL: `url#tag`, `url#branch` and
  `url#<commit>` are git (7 to 40 hex digits is a commit), a `.tar.gz` is a
  tarball. The table form says the same thing longhand.
- **A package needs no manifest.** A directory of `.dr` files is a package
  named by its key; its modules are in `src/` when there is one.
- **Paths are relative to the manifest that wrote them**, so moving a project
  does not change what its dependencies mean.
- **Git must be pinned** with `tag`, `rev` or `branch`. "Whatever is on the
  default branch today" is a moving target, and the build it breaks next week
  will not say why.
- **What a dependency needs travels with it**: its `[build] includes` and
  `host-modules`, and its options (below) -- but not its program-wide
  `defines`, which are the root's to decide.
- **Transitive dependencies are followed**, and a package reached twice is
  compiled once.
- **Conflicts are reported, not guessed at.** A program has one namespace of
  packages, so two different directories under one name cannot both be
  built; `mind` says which two, and who asked for each.

### Versions

There is no registry, so there is nothing to choose between: a program has one
package under each key. A requirement is checked against the `version` the
fetched package declares:

```toml
json = { git = "https://github.com/u/dream-json", tag = "v1.4.0", version = "^1.2" }
util = { path = "../util", version = ">=0.3, <0.5" }
```

`^1.2` is compatible with 1.2 (below 1.0 the minor is the breaking number),
`~1.2.3` takes patch releases, `= < <= > >=` compare, `,` joins, `*` is
anything, and a bare `1.2` means `^1.2`. A mismatch lists every requirement
with where it was written, and whether any version could have met them all.
`std.version` is the grammar.

### `mind.lock`

What the graph resolved to -- every package, its source, its version, for
git the commit checked out, and for anything fetched the hash of its files --
is written to `mind.lock`. Commit it. A build that finds a different commit or
different contents behind the same source (a tag moved, a tarball replaced, a
host compromised) stops and says so; `mind update` fetches again and accepts
what it finds. Editing a dependency in the manifest is not drift; the lock
follows.

The hash is the SHA-256 of one line per file -- the file's own SHA-256 and
its path, sorted -- so it depends on nothing but names and contents: a git
checkout, a tarball and a mirror's copy of the same tree agree. `.git` and
`mind`'s own `.mind-*` markers are not part of it.

Fetched packages are cached in `$MIND_HOME/cache` by URL and revision and
shared between projects. Fetching shells out to `git`, `curl` and `tar`,
which already know about proxies, credentials and certificate stores. A build
trusts the hash it computed when it fetched, rather than rereading every
dependency each time; `mind verify` rereads them, for a cache that may have
been changed by hand.

### Mirrors

Once the lock names a package's bytes, it does not matter who serves them.
When a locked dependency's source cannot be reached, `mind` asks each mirror
for `HEX.tar.gz`, unpacks it, and uses it only if it hashes to what the lock
says. A mirror is a directory or a URL, from `$MIND_MIRRORS` (spaces or
commas between them; tried first, being the machine's answer) or the
manifest:

```toml
[fetch]
mirrors = ["vendor", "https://mirror.example.com/dream"]
```

`mind mirror DIR` writes every fetched dependency there. Commit the directory
to build with no network, put it behind `mind serve` or any static host for a
team, or keep one on a CI runner. A mirror is never trusted, only checked: one
that serves anything else is refused and the next is asked. A copy from a
mirror is kept by its hash, in `$MIND_HOME/cache/sha256`. `mind update` asks
the sources and nothing else, since moving the lock is the point of it.

### Signed releases

A hash protects a version already locked. A signature protects the one you
are about to fetch: a dependency that lists `keys` is used only when it
carries a signature by one of them over the bytes that arrived, however they
arrived -- the source, the cache or a mirror -- and it is checked before
anything it depends on is fetched.

```toml
[dependencies]
json = { git = "https://github.com/u/json", tag = "v1.4", keys = ["ed25519:3d40..."] }

[trust]                         # keys for dependencies at any depth, by key
yaml = ["ed25519:77ab..."]

[fetch]
require-signatures = true       # refuse what no trusted key signed
```

`mind add URL --tag v1.4 --key ed25519:...` writes the first line, and refuses
a release the key did not sign. Keys are Ed25519 (`std.crypto`).

For an author:

```
mind keygen            # once: $MIND_HOME/signing.key, readable by you alone,
                       # and signing.key.revoke, its revocation -- keep it apart
mind sign v1.4         # each release: signs the last commit as v1.4 into mind.sig
git add mind.sig && git commit -m "Sign v1.4" && git tag v1.4
```

What is signed is the tree hash the lock records and the release's name, and
`mind.sig` is left out of the hash, so committing the signature changes
nothing it signs. In a git repository `mind sign` hashes a clone of the last
commit -- exactly what a fetch checks out -- and says so if there are
uncommitted changes it left out; anywhere else it signs the directory as it
stands, which is then what to pack. With no name it signs as `v` and the
manifest's version.

What it protects against:

- **Someone else's bytes.** A release no trusted key signed, or bytes other
  than the ones signed, is refused, and the error says which.
- **An old release in place of a new one.** A dependency pinned to a tag must
  be signed *as* that tag, so `v1.0`'s signature does not pass for `v1.4`.
  And `mind update` refuses to take an older version from the same source --
  a branch or URL moved backwards -- unless given `--allow-downgrade`.
- **Dependencies nobody named a key for.** The lock records who signed each
  package (`signer`) the first time it is seen signed, and from then on it is
  held to that key: a later version unsigned, or signed by someone else, is
  refused, at any depth. `[trust]` names keys up front instead.
- **Rotation.** `mind rotate ed25519:NEW` writes the old key's handover into
  `mind.sig`; sign the release with the new key. Users who trusted the old
  key now trust the new one, and the lock records the old one as `retired`,
  so a release later signed by the old key alone is refused -- what a stolen
  retired key would produce.
- **Revocation.** `mind revoke` publishes the certificate `keygen` wrote,
  which needs no key, so a lost or stolen key can still be revoked. Release
  it signed by another key your users trust. A project that sees it records
  the key under `[revoked]` in its lock and in `$MIND_HOME/revoked`, and every
  project on the machine refuses that key from then on.

What the lock remembers counts while the dependency comes from the same
repository and the project names the same keys; pointing it elsewhere or
naming other keys is choosing to trust anew. The keys you trust are worth
having two of -- one kept offline -- so that a revoked key leaves a trusted
one standing.

### Reproducible builds

A signature says who made the source. An attestation says what that source
builds to, so that a published image -- an installed tool, a release
download -- can be checked against the source it claims to come from:

```
mind attest --release          # build the last commit, sign source -> image
mind reproduce --release       # anyone: rebuild it and compare the bytes
mind reproduce --release --image app.dream    # and check a download is it
mind reproduce json --release  # a dependency, against its author's attestation
```

`mind attest` builds a clean clone of the last commit, as `sign` hashes one,
and writes a `build` statement into `mind.sig`: the source's tree hash, the
compiler's (`dreams --version` names its image's digest), the standard
library's, the profile, and the image's. It leaves the image where `mind
build` would, which is the file to publish. `mind reproduce` rebuilds every
attestation it can and says which match. One made with another compiler or
standard library cannot be repeated here and is reported as skipped, not as
a failure; a rebuild that differs, or nothing reproduced at all, exits 1.
The VM the compiler ran on is recorded too (`dream --version`): a rebuild on
another VM that comes out the same counts, and one that comes out different
is skipped and said to be on another VM, since that is the difference left
to explain it.
For a dependency only attestations by keys the project trusts for it count.

The builds are byte for byte the same anywhere because the compiler is told
to record source paths relative to their package (`--remap-path-prefix`):
`std/src/list.dr` and `app/src/main.dr` rather than wherever they were on the
machine that built them. The compiler, the standard library and the profile
are all that is left to agree on, and the attestation names each.

### The index

Packages need no registry, but finding one by name needs somewhere names are
written down. An index is that: a log, `index.log`, of which release of which
name is at which source and hashes to what. The shared one is
[dream-mindv2/index](https://github.com/dream-mindv2/index), used when no
other is configured; it costs nothing to run and nobody keeping it has to be
trusted.

```
mind search json
mind add json                  # the newest release, held to its author's key
mind add json@^1.2             # the newest a requirement accepts
mind audit                     # any dependency since yanked, or signed by a revoked key
```

Publishing is a signed release and one command. `mind publish` checks the
release is signed in the package, signs an entry, and opens an issue on the
index (with `gh` if it is installed, otherwise a link to open); the index's
GitHub Action checks the entry and appends it. Nobody clones the index.

```
mind sign v1.4 && git add mind.sig && git commit -m v1.4 && git tag v1.4 && git push --tags
mind publish --source https://github.com/you/json
```

Why it can be trusted with nobody in charge -- every reader checks all of it:

- **Keepers admit names.** The log's first line names its keepers and how
  many must sign together. Anyone may publish under a name nobody owns, but
  those releases count for nothing until the keepers admit an owner, and then
  only the owner's do. A name admitted to the wrong key is moved with a
  `transfer`, which brings back the releases the rightful author published.
  An owner can hand a name on (`rotate`).
- **It is a hash chain**: each line holds the hash of the one before, so
  entries can be added and never changed, removed or reordered. Signatures do
  not cover that hash, so an appender can place a signed entry wherever the
  log has got to.
- **Every machine remembers the last head it read** (`$MIND_HOME/index`) and
  refuses a copy that no longer has it, or has fewer entries. The shared
  index's first line is built into `mind`, so even a first read cannot be
  handed another index.
- **It must be fresh.** A timekeeper key, which can sign nothing else, signs a
  checkpoint every day, and a reader refuses an index whose newest checkpoint
  is older than its keepers promised (7 days for the shared one) -- a host
  cannot hold a machine on an old copy to hide a release. `[fetch]
  index-max-age` or `$MIND_INDEX_MAX_AGE` overrides it, `0` for no limit.
- **Releases can be yanked** (`mind index yank NAME RELEASE`) by their owner
  or the keepers. A yanked release is never chosen by a requirement, only by
  asking for it exactly, and `mind audit` reports one a project still uses.
- **What is added is held to the index.** `mind add NAME` writes the author's
  key into the entry and refuses bytes other than the ones the index names,
  and the lock pins them from then on.

Other indexes are `[fetch] indexes` or `$MIND_INDEXES` (`none` for none): a
`github:OWNER/REPO` like the shared one, any `https://` URL serving a copy, or
a directory. `mind index` is the keepers' side -- `init`, `admit`, `transfer`,
`keepers`, `checkpoint`, and `--out FILE`/`cosign FILE`/`submit FILE` for
entries several keepers must sign.

### Cycles

Every kind of dependency means "must be ready first", so a loop cannot be
built -- including one through a build script. It is reported as the whole
loop, each edge with the manifest that made it:

```
mind: these packages need each other, so none of them can be built first:
  app      uses         sqlite   (mind.toml)
  sqlite   builds with  codegen  (../sqlite/mind.toml)
  codegen  uses         app      (../codegen/mind.toml)
```

## Build scripts

A package may carry a `build.dr` beside its manifest, for what it needs made
before it compiles and cannot write by hand: a generated module, a file to
embed, a C library, a switch that depends on the machine. **It is optional**;
a package without one builds exactly as if scripts did not exist.

A script is a pure function from a context to a plan, written with
`std.build`:

```dream
import std.build;
import std.build.command;

let plan ctx =
    build.empty
    |> build.module "version" (build.write "version.dr" ("let v = \"" + build.version ctx + "\";"))
    |> build.payload "table" (command.make "table" "gen-table" [command.file "table.csv", command.out "t.bin"])
    |> build.define "generated";
```

`build.module` makes `<package>.version` importable; `build.payload` embeds a
file in the image; `build.define` sets a `when` flag for this package alone.
`std.build.cc` compiles C and C++ with GCC, Clang, MSVC or through CMake from
one description.

Every step is cached by what it was given and the contents of what it reads,
in one cache shared by every project on the machine, so a build where nothing
changed runs no script and starts no VM -- it costs a `stat` per input. Steps
run `-j` at once.

A script sees only the environment variables its manifest lists, and is
compiled against `[build-dependencies]`, a namespace of its own:

```toml
[build]
env = ["CC", "PKG_CONFIG_PATH"]
script = "tools/build.dr"        # when it is not build.dr

[build-dependencies]
codegen = "../codegen"
```

[mind/std/docs/build.md](https://github.com/dream-mindv2/std/blob/main/docs/build.md) is the whole design.

### Goals

A plan can name things to make on request -- `build.goal name goal` -- and
`mind build NAME` makes them instead of the program. The repository's own
`build.dr` is the example: `mind build vm` builds the VM with `std.build.cc`,
and `mind build default` the VM, the compiler and `mind`.

## Tests

`mind test` runs every test a project has, at once: each package's **units**
(its `when test` blocks, compiled with `--test` and run) and the **checks** its
build script declares. A test is named for its package, and a name narrows:

```
mind test                       # everything
mind test dreams                # one package's
mind test dreams.bootstrap      # one check
```

A check is a step that passes when it succeeds, run only by `mind test` and
every time:

```dream
let plan ctx =
    build.empty
    |> build.check "golden" (command.check ctx "golden" (command.toolchain ctx) "tests/golden.sh" []);
```

`command.toolchain ctx` hands the check the VM and compiler this build uses,
as `DREAM` and `DREAMS`. A library with no program names the file its tests
are gathered from: `[test] entry = "all.dr"`.

A **workspace** tests several packages as one project. The repository's own
`mind.toml` is one:

```toml
[workspace]
name = "dream"
members = ["dreams", "lucid", "mind/std", "mind/tool"]

[build]
compiler = "build/dreams.dream"
```

## Options and profiles

A package declares what it can be built as. Each option has a type -- `bool`,
`integer`, `string`, or a list of choices -- and a default:

```toml
[options]
vendored = { type = "bool", default = false, doc = "build sqlite from source" }
threads  = { type = ["off", "single", "multi"], default = "multi" }
cache_mb = 64
```

`when vendored` reads it inside the package and `when sqlite.vendored` from
anywhere else. A setting is decided by, the later winning: the default; the
package's `[build] defines`; `[config.KEY]` in any manifest that depends on
it; the profile's `[profile.NAME.config.KEY]`; and `-D KEY:name=value`. Two
dependencies that configure a third two ways are a conflict for the root to
settle. A name or value the package does not declare is an error that lists
what it accepts, never a setting quietly ignored.

A dependency can hang on an option -- `sqlite_sys = { path = "..", when = "not vendored" }`
-- in the compiler's `when` grammar. An edge whose condition is false is not
fetched, not built and not a conflict.

A **profile** is a named way to build the whole program:

```toml
[profile.release]
defines = ["release"]
flags   = ["--no-opt"]
target  = "linux"

[profile.release.config.sqlite]
threads = "multi"
```

`--profile NAME` picks one, `--release` is `--profile release`, `debug` is
the default, and only the root's profiles count. The image goes to
`target/<profile>/<name>.dream`, with the platform first when a target is
stated (`target/linux/release/`), so no build overwrites another's image.

`debug = true` -- in `[build]` for every profile, or in a profile's section
for that one, which says first -- builds the image with what a debugger
reads: the name of each function's locals, so that `dream --debug` shows
`items = [..]` rather than a slot number. It is off unless written, so a
build that is only for running carries none of it:

```toml
[build]
debug = true

[profile.release]
debug = false
```

## Applications

A package with a `[graphics]` section is a std.graphics application: its
program is the frontend, which runs in a page on the browser VM, and `mind
build` makes the whole of it -- `assets/`, a static site holding the page, its
scripts, the browser VM and the frontend compiled for any VM, and
`backend.dream` beside it when there is a backend.

```toml
[graphics]
backend = "src/backend.dr"            # a native Dream backend, for the desktop
js = ["web/chart.mjs"]                # the application's own modules
css = ["web/theme.css"]               # and stylesheets
assets = ["images"]                   # files and directories, shipped as they are
connect = ["https://api.example.com"] # origins the page may fetch from
base = "/"                            # where it is served, when routes are paths
```

`mind run` builds it and serves `assets/` on 127.0.0.1 (`--port`, default
8000), answering a path that names no file with the page, so a route reloads;
`mind run --desktop` opens it in a window instead, backend and all. What opens
is the build's one image, `target/<profile>/<name>.dream`: the backend's program
with the page carried as `graphics/` payloads, which a Linux VM runs in a window
(WebKitGTK 4.1 installed), so `mind install` installs an application as it does any
program and `dream -x NAME` opens it. The page's
own files come with the standard library; the browser VM is `--runtime DIR`,
then `[graphics] runtime`, then `$DREAM_BROWSER`, then the installation's
`browser/`, then a `build-browser/` at or above the working directory.
mind/std/docs/graphics.md is the guide.

## Finding the compiler and the library

The compiler is `--compiler`, then `[build] compiler`, then `$DREAMS`, then
`dreams.dream` from the installation (`$MINDV2_PATH`). A name ending in
`.dream` is run by the VM (`$DREAM`, default `dream`); anything else is run
directly.

The standard library is `$MIND_STDLIB`, then `$MIND_HOME/std`, then a `mind/`
directory holding `std` at or above the working directory -- which is what
makes this repository work with no configuration -- and last the
installation's copy: the first directory of `$MINDV2_PATH` (or `~/.mindv2`)
holding `std`, which is where `just install` puts it. A checkout comes before
the installation, so an installed library never shadows the one being worked
on.

## Environment

| | |
|---|---|
| `DREAMS` | the compiler |
| `DREAM` | the VM that runs images (default `dream`) |
| `MINDV2_PATH` | the installation: where `dreams.dream` is found |
| `MIND_STDLIB` | the directory holding `std` |
| `DREAM_BROWSER` | the browser VM an application ships: a directory holding `dream-browser.mjs` and `.wasm` |
| `MIND_HOME` | fetched packages, the build cache and the unit cache (default `~/.mind`) |
| `MIND_INDEXES` | the indexes to look names up in, before `[fetch] indexes`; `none` for none |
| `MIND_INDEX_MAX_AGE` | how old an index's newest checkpoint may be, overriding its keepers (`14d`; `0` for no limit) |
| `MIND_MIRRORS` | where to fetch a locked package whose source is down, before `[fetch] mirrors` |
| `MIND_BUILD_CACHE` | where build steps are cached (default `$MIND_HOME/build`) |
| `MINDV2_HOME` | where toolchains are installed (default `~/.mindv2`) |
| `MIND_TOOLCHAIN_SITE` | where toolchain releases are announced, a URL or a directory (default `https://dream-mindv2.github.io/toolchain`) |
| `MIND_TOOLCHAIN_KEYS` | keys trusted to sign toolchains besides the built-in one: a private mirror's |
| `MIND_UNITS` | where the compiler keeps each module's work between builds (default `$MIND_HOME/units`; `off` for none). Entries unused for 30 days are removed |

## Layout

The modules are in `src/`; `build.dr` beside the manifest is the build script
whose checks `mind test mind` runs after the units.

| | |
|---|---|
| `main.dr` | the commands and their arguments |
| `manifest.dr` | reading `mind.toml`, and the line edits `add` and `remove` make |
| `fetch.dr` | a dependency to a directory, fetching when needed; the tree hash, the store and mirrors |
| `build.dr` | the dependency graph, options, and calling the compiler (the module, not the script) |
| `script.dr` | running build scripts and folding what they make into the compile |
| `lock.dr` | `mind.lock`, and what counts as drift: a commit or a hash |
| `sign.dr` | signed releases: keys, `mind.sig`, and what is signed |
| `docs.dr`, `documentation/` | `mind docs`: guides, API pages, examples run, links, the theme |
| `serve.dr` | `mind serve` and `mind docs serve` |
| `graphics.dr` | `[graphics]`: an application made, and the page's policy |
| `pack/` | `mind pack` and every package format it writes |
| `config.dr`, `util.dr` | settings, paths and files |

## Developing mind

`mind` is developed inside the [Dream workspace](https://github.com/Custards1/dream),
where this repository is checked out at `mind/tool` beside the VM, the
compiler and the standard library it is built and tested against:

```sh
git clone --recursive https://github.com/Custards1/dream
cd dream
just mind               # build/mind, from this checkout
just test-mind          # the units, then the graph, options, scripts, docs and book suites in tests/
mind test mind          # the same, at once
```

The suites in `tests/` find the VM, the compiler and the library by their
places in the workspace, so they run from there.

## Packaging and documentation

[PACKAGING.md](PACKAGING.md) is `mind pack`: the formats, and the `[ship]`
manifest sections that describe a package. (`mind pack` is the former
standalone Ship packager; replace `ship FORMAT` with `mind pack FORMAT`.)

[DOCUMENTATION.md](DOCUMENTATION.md) is `mind docs` and `mind serve`: writing
guides and `///` comments, runnable examples, links into the reference, and
serving the site.
