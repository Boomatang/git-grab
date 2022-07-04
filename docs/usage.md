# Usage

## Initial Setup
There is are a few setup steps that can be down to make the usage of `git-grab` easier.
These steps can be done at any time.

Setting the default path for where repos will be stored can be done by an environment variable.
Add `export GRAB_PATH=<full/path>` to your shells rc file.
This sets the default path for the commands that will be covered later.

Creating the files required for lookups later can also be done now.
For the first time that the command is run the `--new-file` flag must be pasted.
By default, the path `GRAB_PATH` is included but more can be added using the `-p` flag.
```shell
grab list --generate --new-file

or

grab list --generate --new-file -p <extra/path>
```
The `list` command is explained later.

## Commands
### add
The `add` commands will clone git repos and store these in a structured manner.
The structure that is used.
```
$GRAB_PATH
└── <source controll website>
        └── <Org/Username>
            ├── <repo 1>
            └── <repo 2>
```

| flag      | Description                                   | type            |
|-----------|-----------------------------------------------|-----------------|
| -f --file | File listing repos to be cloned (unsupported) | file location   |
| -u --url  | ssh url of repo to be cloned                  | ssh@url         |
| -p --path | System path location to clone repo to         | folder location |
| -h --help | Shows command help                            |                 |

The `--file` flag feature will be removed in later release due to a lack of use.
If this is a feature that you use please share.

After adding a new repo it to the default or stored path it is a good idea to run `grab list --generate`.
This will update the list of repo that can be searched later.

#### Example use cases

Cloning a new repo to the default defined by `GRAB_PATH`.
```shell
grab add -u git@github.com:Boomatang/git-grab.git
```

Clone a repo to a none default location.
One reason this might want to be done is to temporarily clone a repo.
```shell
grab add -u git@github.com:Boomatang/git-grab.git -p /tmp
```

### fork
The `fork` command adds remotes to the cloned repos.
This is done with using the same `git@url` that would be used the clone the remote locally.
Currently, this feature only work with repos on github.com.

| Flags      | Description                          | Type            |
|------------|--------------------------------------|-----------------|
| -p, --path | Path to repo if not in default paths | Folder location |
| -h, --help | Display help text                    |                 |

When the repo is in the default paths state in the `list` command there is no need to use the `-p` flag.
The repo will be found.

After using the command the remote will be added using the username of the fork.
The git remotes can be listed by using `git remote`.

#### Example usage

Adding a remote to existing repo.
```shell
grab fork git@github.com:<username>/git-grab.git
```

Adding a remote to repo in none default location.
```shell
grab fork -p /tmp/repo git@github.com:<username>/git-grab.git
```

### list
The `list` command can be used to list all the repos that have being configured and in the default path.

| Flags        | Description                                                                             | Type             |
|--------------|-----------------------------------------------------------------------------------------|------------------|
| -o, --org    | List only repos from give org/user                                                      | string           |
| -w, --wide   | Shows more details on the repo                                                          | bool             |
| --generate   | Generates teh repo_list.yaml file                                                       | bool             |
| -p           | Paths to include in generate function                                                   | folder locations |
| --show-paths | List the paths from grab_paths.yaml that is used to generate the current repo_list.yaml | bool             |
| --new-file   | Creates a new grab_paths.yaml file                                                      | bool             |
| -h, --help   | Display help text                                                                       |                  |

### path
The `path` command prints the path to a repo.
This can take a number that is shown side the repo from the list command or the org/repo string.

| Flags        | Description       | Type |
|--------------|-------------------|------|
| -h, --help   | Display help text |      |

#### Example use case

Print the path to a repo
```shell
$ grab path Boomatang/git-grab
<path/to/repo/git-grab>

or

$ grab path 2
<path/to/repo/git-grab>
```

A common use case is to combine this with the `cd` command to change to repo location.
```shell
cd $(grab path Boomatang/git-grab)
```
