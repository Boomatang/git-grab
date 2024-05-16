# Git Grab

Git Helper Tool used to quickly add repo's to the users system for an external source.
With not having to worry about were the repo is being stored.

Initial Goals of the project

-   Create a tool to help download git repos
-   Repos are sorted by which site and user they belong to.
```
code
└── github.com
    └── Boomatang
      ├── dotfiles
      └── git-grab
```

## Installation

To install grab, run this command in your terminal:

`git` needs to be installed before using `git-grab`

```
$ pipx install git-grab
```

## Usage

### Overview
```
grab <url-to-repo>
grab -r <url-to-remote-repo>
grab --help
```

### Configuring
The environment variable `GARB_PATH` can be set to insure the default local of for storing the repos.
At any time the environment variable can be overridden by the `-p` flag.

### Cloning a repo
To cloning a repo can be done using both the ssh or https routes.
When cloning, the data is stored in the path defined in `GRAB_PATH`.
```shell
grab <repo route>
```
To override the path at run time the `-p` flag can be used.
```shell
grab <repo route> -p <some/other/path>
```

### Adding remotes to repos.
The `-r` flag can be used to say the repo path is a remote of an existing repo.
```shell
grab -r <repo route>
```
This adds the `repo route` to all cloned repos in the path where the repo name matches.
Using the `-p` flag allows setting the path where to search for repos.
```shell
grab -r <repo route> -p <some/other/path>
```

## Warning
All the functions are case-sensitive.
This can be problematic when adding remotes to existing cloned repos.
