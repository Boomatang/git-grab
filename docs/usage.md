# Usage

## Overview
```
grab <REPO>...
grab --remote <REPO>...
grab --standard <REPO>...
grab --help
grab --version
```

## Repositories
The Zig port expects SSH-style repo URLs that start with `git` and end in `.git`,
for example:
```
git@github.com:Boomatang/git-grab.git
```

## Configuration
`GRAB_PATH` sets the default base directory for storing repos. You can override
it per run with `--path`.

`--temp` downloads to the OS temp directory instead of `GRAB_PATH` or `--path`.

`--temp` and `--path` are mutually exclusive.

## Cloning a repo
Default behavior uses a worktree-based clone. For a standard clone, use
`--standard`.
```shell
grab <REPO>
grab --standard <REPO>
```
Override the path at run time:
```shell
grab <REPO> --path <some/other/path>
```

## Adding remotes to repos
`--remote` treats the repo URL as a remote to add to existing clones with the
same repo name under the configured path.
```shell
grab --remote <REPO>
```
Search a specific path:
```shell
grab --remote <REPO> --path <some/other/path>
```

## Warning
All matching is case-sensitive, which can be problematic when adding remotes.
