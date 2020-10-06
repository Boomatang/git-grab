Git Grab
========

Git Helper Tool used to quickly added repo's to the users system for an
external source. With not having to worry and were the repo is been
stored.

Initial Goals of the project
----------------------------

-   Create a tool to help download git repos
-   Repos are sorted by which site and user they belong to.
```
code
└── github.com
        └── Boomatang
            ├── dotfiles
            └── git-grab
```

Usage
-----

### Main usage
```
grab add -u <url-to-repo>
grab fork <url-to-forked-repo>
grab --help
grab <command> --help
```
### List repos

#### Configure
To list the repos on the current system we most first generate a
list of the repo's. By default the first time this uses the path that is
set in `GRAB_PATH`.

```
grab list --generate
```

Each time after the paths listed in paths.yaml. The contents of
this file and the path to the file can be shown with.
```
grab list --show-paths
```

To add more than one path when generating the list use the flag `-p`
followed by the path of the folder you wish to include. `-p` can be
added as many times as required.

```
grab list --generate -p <path/to/file1> -p <path/to/file/2>
```

If there is an exiting paths.yaml the folder paths will get added
to the file.


When a paths.yaml exists this will be used when generating the
list. A new paths.yaml file can be created using.
```
grab list --generate --new-file
```

#### Usage
The list of repos that have been generated are saved in a file called
repo_list.yaml.

To get the basic list as shown below. These will be sorted by Org then
Repo name.
```
$ grab list

#  Org/Repo
-- -------------------
1  Boomatang/dotfiles
2  Boomatang/git-grab
3  github/gitignore

```

The `--wide` flag will display more information, such as the path to the
repo.
```

$ grab list --wide

#  Org/Repo             Location
-- -------------------- ------------------------
1  Boomatang/dotfiles   <path/to/repo/dotfiles>
2  Boomatang/git-grab   <path/to/repo/git-grab>
3  github/gitignore     <path/to/repo/gitignore>
```

List the repos belonging to a Org by using the `--org` or `-o` flags.
These feature will not be case sensitive.
```
$ grab list --org boomatang

#  Org/Repo
-- -------------------
1  Boomatang/dotfiles
2  Boomatang/git-grab

```

### Path to Repos
It is possible to get the system path to a repo using the `grab path`
command.

The example below opens the git-grab repo by stating the org/repo, the
list number or project url. The project url can have the path to a file
or pull request.
```
$ grab path Boomatang/git-grab
<path/to/repo/git-grab>
```
or
```
$ grab path 2
<path/to/repo/git-grab>
```
or
```
 $ grab path http(s)://github.com/Boomatang/git-grab
<path/to/repo/git-grab>
```
