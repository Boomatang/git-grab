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


@grab_cli.command(help="Update all repos")
@click.option("-n", "--name", help="Name repo to be updated")
def update(name):

    if name:
        grab.update_repo(name)
    else:
        grab.update_repos()


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
@click.option(
    "--domain",
    type=click.Choice(["Site", "ORG", "Username"]),
    help="List the top level data under " "that domain.",
)
@click.option(
    "-f",
    "--filter",
    "filter_",
    multiple=True,
    help="Filter the list by multiple values",
)
@click.option("-d", "--detail", is_flag=True, help="Add more detail to the output")
def list_repos(domain, filter_, detail):
    # TODO this needs much working out to get it working fully

    grab.list_repos(detail)

    print("\nI have no idea how to create the filters or do the domain stuff")


@grab_cli.command(help="Remove a repo")
@click.argument("name")
@click.confirmation_option(
    prompt="Are you sure you want to remove the repo? This can not be undo."
)
@click.option(
    "--all", is_flag=True, help="Removes all the repos from the set up", hidden=True
)
def remove(name, all):
    if not all:
        grab.remove_repo(name)

    if all:
        if click.confirm(
            "Are you really sure? This removes all the repos from the system."
        ):
            grab.remove_all_repos()


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
