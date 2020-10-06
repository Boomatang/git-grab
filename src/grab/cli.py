import click
import grab

PREFIX = "GRAB"

path_message = (
    "A path is required, set system variable 'export GRAB_PATH=/path/to/code' or pass in the path using "
    "the '--path' keyword"
)


@click.group(
    invoke_without_command=False,
    context_settings={
        "help_option_names": ["-h", "--help"],
        "auto_envvar_prefix": PREFIX,
    },
)
@click.version_option(version=grab.version())
@click.pass_context
def grab_cli(ctx):
    """Run the grab application."""


@grab_cli.command(
    help="Add repos from file"
)  # TODO add this back in when it is 7.1^ --> , no_args_is_help=True)
@click.option("-f", "--file", "file_", help="File name to import")
@click.option("-u", "--url", "url", help="URL of repo to import")
@click.option("-p", "--path", envvar=f"{PREFIX}_PATH", help="Base path for repos")
def add(file_, url, path):
    if file_ and url:
        print("Only select a file or a url")
        exit(1)

    if path is None:
        print(path_message)
        exit(1)

    if file_ is None and url is None:
        print("A file or url is required")
        exit(1)

    grab.add_repos(file_, url, path)


@grab_cli.command(name="list", help="List all the current repos")
@click.option("-o", "--org", help="Show only repos matching the org.")
@click.option("-w", "--wide", is_flag=True, help="Show more details about the repos")
@click.option("--generate", is_flag=True, help="Generate the repo_list.yaml file.")
@click.option(
    "-p", "paths", multiple=True, help="Paths to be included in the generate function."
)
@click.option(
    "--show-paths",
    "show",
    is_flag=True,
    help="List the paths from grab_paths.yaml that is used to generate "
    "the current repo_list.yaml file",
)
@click.option(
    "--new-file", "new_file", is_flag=True, help="Create a new grab_paths.yaml file"
)
@click.argument("grab_path", envvar=f"{PREFIX}_PATH")
def list_repos(org, wide, generate, paths, show, new_file, grab_path):

    if len(paths) > 0 and not generate:
        print("-p can only be used with --generate")
        print("Aborting...")
        exit(1)

    if new_file and not generate:
        print("--new-file cna only be used with --generate")
        print("Aborting...")
        exit(1)

    if (org is not None or wide) and (generate or show):
        print("--org or --wide can not be used with --generate or --show-paths")
        print("Aborting...")
        exit(1)

    if generate and show:
        print("--generate and --show-paths can not be used together")
        print("Aborting...")
        exit(1)

    if generate:
        grab.generate(grab_path, paths, new_file)
    elif show:
        grab.show_paths()
    else:
        grab.list_repos(org, wide)


@grab_cli.command(
    help="Add remote users fork. This feature is only working with github.com, on public repos and ssh "
    "routes. Requires the Git clone ssh/url string."
)
@click.argument("fork_path")
@click.option("-p", "--path", envvar=f"{PREFIX}_PATH", help="Base path for repos")
def fork(fork_path, path):
    if path is None:
        print(path_message)
        exit(1)
    grab.fork(fork_path, path)


@grab_cli.command(
    "path",
    help="Get the system path for a Repo. The REPO is a combination of "
    "org/repo in the same format given by the list command or the line number given by the "
    "list command.",
)
@click.argument("repo")
def path_to_repo(repo):
    grab.path_to_repo(repo)
