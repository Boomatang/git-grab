# Git Grab

Git-Grab is a helper tool that clones repositories into a structured directory
layout so you do not have to remember where projects live.

## Key features
- Worktree-first cloning workflow (standard clone available)
- Structured paths by host and owner
- Add a remote to existing local clones
- Optional temp directory cloning
```
code
└── github.com
    └── Boomatang
      ├── dotfiles
      └── git-grab
```

## Installation

`git` must be installed before using `git-grab`.

### Prebuilt binary
1. Download the latest release archive for your OS/arch.
2. Extract it and move the `grab` binary somewhere on your `PATH`.
3. Verify:
```
grab --version
```

### Build from source (Zig)
1. Install Zig (matching the version supported by this repo).
2. From the repository root, build the binary:
```
zig build -Doptimize=ReleaseSafe
```
3. The binary is created at:
```
zig-out/bin/grab
```
4. Optional: run it directly via Zig:
```
zig build run -- <args>
```

## Usage

### Overview
```
grab <REPO>...
grab --remote <REPO>...
grab --standard <REPO>...
grab --help
grab --version
```

### Repositories
The Zig port expects SSH-style repo URLs that start with `git` and end in `.git`,
for example:
```
git@github.com:Boomatang/git-grab.git
```

### Configuration
`GRAB_PATH` sets the default base directory for storing repos. You can override
it per run with `--path`.

`--temp` downloads to the OS temp directory instead of `GRAB_PATH` or `--path`.

`--temp` and `--path` are mutually exclusive.

### Cloning a repo
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

### Adding remotes to repos.
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

## Dev
### Creating the changelog

On new changes a news fragment is required.
This can be created by and news fragments to the `changes` directory.
These files are should have the following naming schema `<issue id>.<feature|bugfix|dic|removal|misc>`.
Using `towncrier create -c "change message" <file name>` will also create the file for you in the correct location.

