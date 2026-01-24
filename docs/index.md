# Welcome to Git-Grab (Zig port)
Git-Grab is a helper tool that clones repositories into a structured directory
layout so you do not have to remember where projects live.

## Key features
- Worktree-first cloning workflow (standard clone available)
- Structured paths by host and owner
- Add a remote to existing local clones
- Optional temp directory cloning

## Example layout
```
code
└── github.com
    └── Boomatang
        ├── dotfiles
        └── git-grab
```

## Quick start
```
grab git@github.com:Boomatang/git-grab.git
```
