# Welcome to Git-Grab

This application is built to give a helping hand when working with
multiply git repos. The use case is for downloading repos to your local
machine in a structured format.

## Key Features
- Download git repos from remote sites. Github.com, Bitbucket.org &
  custom GitLab instances.
- Download repos to a formatted structure.
- Add forks to currently installed repos.
- List currently install repos.
- Display paths to repos.

# Usage

See [usage page](usage.md) for details, but here's a demo of how it works:

```
$ grab add -u git@github.com:Boomatang/git-grab.git

$ grab list

#  Org/Repo
-- -------------------
1  Boomatang/dotfiles
2  Boomatang/git-grab
3  github/gitignore

$ grab path Boomatang/git-grab
/home/boomatang/code/github.com/Boomatang/git-grab

$ grab fork git@github.com:NewFork/git-grab.git

$ grab --help
Usage: grab [OPTIONS] COMMAND [ARGS]...

  Run the grab application.

Options:
  --version   Show the version and exit.
  -h, --help  Show this message and exit.

Commands:
  add   Add repos from file
  fork  Add remote users fork.
  list  List all the current repos
  path  Get the system path for a Repo.

```



