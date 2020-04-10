import pathlib
import os
import shutil
import subprocess
from pprint import pprint

import requests
import click
from typing import List
from tabulate import tabulate

from dataclasses import dataclass, asdict

from pony.orm import select, db_session, commit, delete

import grab
from grab.helper import is_on_branch, get_branch_name
from grab.model import setup_db_connection, Repo

__all__ = [
    "update_repos",
    "update_repo",
    "add_repos",
    "list_repos",
    "remove_repo",
    "remove_all_repos",
    "fork",
    "version",
]


@dataclass
class SshInfo:
    site: str = None
    user: str = None
    repo: str = None
    ssh: str = None

    @classmethod
    def from_dict(cls, d):
        return SshInfo(**d)

    def to_dict(self):
        return asdict(self)


@dataclass
class DbRepo:
    name: str = None
    path: str = None
    clone: str = None

    @classmethod
    def from_dict(cls, d):
        return SshInfo(**d)

    def to_dict(self):
        return asdict(self)


# Tested #################################################################


def update_repo(name):
    """Update all the repos in the system"""
    print(f"Update repo {name}")


##################################################################


def update_repos():
    """Update all the repos in the system"""
    setup_db_connection()
    repos = get_repo_paths_from_db()

    for repo in repos:
        work_with_repo(repo)


def work_with_repo(repo):
    print(f"Updating in {repo}")
    os.chdir(repo)
    past_branch = None

    if not is_on_branch():
        past_branch = stash_changes_and_checkout_master()

    if is_on_branch():
        do_git_pull()
        restore_past_branch(past_branch)
    else:
        print("Check repo status, error when updating")
        print(f"Repo location: {repo}")
        exit(1)


def add_repos(file_name, url, base_path):
    base_path_check(base_path)
    setup_db_connection()

    if file_name:
        add_repos_from_file(file_name, base_path)
    elif url:
        add_repo_from_url(url, base_path)
    else:
        raise RuntimeError("You should not have gotten this far")


def add_repos_from_file(file_path, base_path):
    """Add repos from a file"""
    exit_program_if_file_does_not_exist(file_path)

    print("Create repos from a file")
    contents = parse_file_contents(file_path)
    process_contents(contents["site"], base_path)


def add_repo_from_url(url, base_path):
    """Add repos from a file"""
    print("Create repo from a URL")
    contents = parse_url_content(url)
    if contents is not None:
        process_contents(contents["site"], base_path)


def list_repos(detail):
    """List all the repos in the system"""
    setup_db_connection()
    if detail:
        print("There is more detail been printed")
    with db_session:
        repos = select(r for r in Repo)

        if len(repos) > 0:
            print(format_print_table(repos))
        else:
            print("No entries found")


def remove_repo(name):
    """Remove a repo from the system defaults to one"""
    setup_db_connection()
    print(f"Removing a repo: {name}")
    repo: Repo = get_repo_by_name_from_db(name)

    # check status of repo
    check_repo_status_ok_or_exit(repo.path)

    # remove files
    forcefully_remove_repo_folders(repo.path)
    # ensure files have been removed
    if check_folders_have_been_removed(repo.path):
        # remove entry from db
        remove_repo_from_db(repo.id)
    else:
        print(f"Unable to remove folder for {repo.name}")
        exit(1)

    print("Repo removed.")


def remove_all_repos():
    """Remove a repo from the system defaults to one"""
    setup_db_connection()
    names = get_repo_names()
    with db_session:
        for name in names:
            remove_repo(name)


@db_session
def get_repo_names():
    return select(r.name for r in Repo)


def base_path_check(base_path):
    path = pathlib.Path(base_path)
    print("Checking if base path exists")
    if path.exists():
        if path.is_dir():
            return
    else:
        print(f"Folder {str(path)} does not exist")

    create_base_folder(str(path))


def create_base_folder(path):
    if click.confirm(f"Try create folder : {path}"):
        pathlib.Path(path).mkdir(parents=True)
        base_path_check(path)
    else:
        print("Exiting program")
        exit(0)


def exit_program_if_file_does_not_exist(file_name):
    path = pathlib.Path(file_name)
    if path.exists():
        if path.is_file():
            return
    else:
        print(f"File '{str(path)}' does not exist")
        exit(1)


def parse_file_contents(file_path):

    line_data = []
    with open(file_path, "r") as f:
        for line in f:
            line_data.append(parse_line_contents(line))

    data = compile_line_data(line_data)
    return data


def parse_line_contents(line):
    if line.startswith("git@"):
        return parse_ssh_line(line)
    else:
        print(f"File line is wrong format \n ==> '{line}'")


def parse_url_content(url):
    if url.startswith("git@"):
        return work_with_SSH_url(url)
    elif url.startswith("https"):
        return work_with_http_url(url)
    else:
        print(f"URL is wrong format \n ==> '{url}'")

    return None


def work_with_http_url(http):
    data = [parse_http_line(http)]
    return compile_line_data(data)


def work_with_SSH_url(ssh):
    data = [parse_ssh_line(ssh)]
    return compile_line_data(data)


def parse_http_line(line):
    http = line.strip("\n")
    split = line.split("://")
    split = split[1].split(".")
    split = split[:-1]
    split = ".".join(split)
    split = split.split("/")
    site = split[0]
    user = split[1]
    repo = split[2]
    data = SshInfo(site, user, repo, http)
    print(data)
    return data


def parse_ssh_line(line):
    ssh = line.strip("\n")
    split = line.split("@")
    split = split[1].split(":")
    site = split[0]
    split = split[1].split("/")
    user = split[0]
    split = split[1].split(".")
    repo = split[0]
    data = SshInfo(site, user, repo, ssh)
    return data


def process_contents(contents, base_path):
    folders, folders_and_ssh = create_required_folders(contents, base_path)
    create_user_folders(folders)
    errors = clone_git_repos(folders_and_ssh)

    add_repos_to_db_if_not_in_errors(contents, base_path, errors)

    if len(errors) > 0:
        print_git_clone_errors(errors)


def compile_line_data(line_data: List[SshInfo]):
    data = {"site": {}}

    for line in line_data:
        if line.site not in data["site"].keys():
            data["site"].setdefault(line.site, {})

        if line.user not in data["site"][line.site].keys():
            data["site"][line.site].setdefault(line.user, {})

        if line.repo not in data["site"][line.site][line.user].keys():
            data["site"][line.site][line.user].setdefault(line.repo, line.ssh)

    return data


def create_required_folders(contents, base_path):
    paths = []
    locations = []
    for site in contents.keys():
        for user in contents[site]:
            base = str(pathlib.Path(base_path, site, user))
            locations.append(base)
            for repo in contents[site][user]:
                ssh = contents[site][user][repo]
                paths.append((base, ssh))

    return locations, paths


def create_user_folders(folders):
    for folder in folders:
        folder = pathlib.Path(folder)
        folder.mkdir(parents=True, exist_ok=True)

        if not folder.is_dir():
            print(f"Error creating: {str(folder)}")


def clone_git_repos(folders_and_ssh):
    messages = []
    for unit in folders_and_ssh:
        working_dir = pathlib.Path(unit[0])

        if working_dir.is_dir():
            os.chdir(working_dir)
            message = git_clone(unit[1])

            if message is not None:
                messages.append(message)
        else:
            print("Folders don't exist")
            exit(1)

    return messages


def git_clone(ssh):
    message = None

    print(f"Cloning {ssh} to {os.getcwd()}...\t", end="")
    value = subprocess.run(["git", "clone", ssh], capture_output=True)

    if value.returncode != 0:
        message = {"repo": ssh, "error": value.stderr.decode()}
        print("Failed")
    else:
        print("Completed")

    return message


def print_git_clone_errors(errors):
    print()
    for error in errors:
        print("#" * 30)
        print(f"Error cloning {error['repo']}")
        print("#" * 30)
        print("\nFollow error was raised by git clone")
        print("-" * 30)
        print(error["error"])
        print("-" * 30)
        print()


def add_repos_to_db_if_not_in_errors(contents, base_path, errors):
    data = []

    errors = get_list_of_error_urls(errors)
    print(errors)

    for site in contents.keys():
        for user in contents[site].keys():
            for repo in contents[site][user].keys():

                data.append(
                    DbRepo(
                        repo,
                        str(pathlib.Path(base_path, site, user, repo)),
                        contents[site][user][repo],
                    )
                )

    add_repos_not_in_errors(data, errors)


@db_session
def add_repos_not_in_errors(data, errors):
    for d in data:
        if d.clone not in errors:
            Repo(name=d.name, path=d.path, clone=d.clone)

    commit()


def get_list_of_error_urls(errors):
    data = []
    for error in errors:
        data.append(error["repo"])

    return data


def format_print_table(repos):
    header = ["Name", "Path"]
    data = []
    for repo in repos:
        data.append((repo.name, repo.path))

    return tabulate(data, header)


def git_status():
    """
    Checks for git status
    :return: True if there is no uncommitted files
    """
    output = subprocess.run(["git", "status", "-s"], capture_output=True)
    if len(output.stdout) == 0:
        return True
    else:
        return False


def stash_changes_and_checkout_master():
    past_branch = get_branch_name()
    if not git_status():
        status = subprocess.run(["git", "stash"], capture_output=True)
        status.check_returncode()

    branch = subprocess.run(["git", "checkout", "master"], capture_output=True)
    branch.check_returncode()

    return past_branch


def restore_past_branch(branch):
    if branch is not None:
        status = subprocess.run(["git", "checkout", branch], capture_output=True)
        status.check_returncode()

        if is_on_branch(branch):
            status = subprocess.run(["git", "stash", "pop"], capture_output=True)
            status.check_returncode()


def do_git_pull():
    status = subprocess.run(["git", "pull"], capture_output=True)
    if status.returncode != 0:
        print(status.stderr.decode())
        exit(1)
    else:
        print(status.stdout.decode())


@db_session
def get_repo_paths_from_db():
    return select(r.path for r in Repo)[:]


@db_session
def remove_repo_from_db(id):
    delete(r for r in Repo if r.id == id)
    commit()


def check_folders_have_been_removed(path):
    repo = pathlib.Path(path)

    if not repo.exists():
        return True
    else:
        return False


def forcefully_remove_repo_folders(path):
    shutil.rmtree(path)


def check_repo_status_ok_or_exit(path):
    os.chdir(path)
    if not git_status():
        if not click.confirm("Repo has uncommitted changes. Proceed to remove Repo."):
            print("Cancelled by user.")
            print("System Exit")
            exit(0)


@db_session
def get_repo_by_name_from_db(name):
    result = select(r for r in Repo if r.name == name)[:]

    if len(result) != 1:
        print("To many repos found")
        return None
    else:
        return result[0]


def fork(fork_path, src=None):
    print(f"Adding Fork: {fork_path}")

    username, repo = get_username_and_repo(fork_path)
    if username is None or repo is None:
        print("Not find username or repo")
        exit(1)

    data = get_api_repo_data(username, repo)

    if data["fork"] == False:
        print("Repo is not a fork. Aborting")
        return

    parent = get_parent_repo_data(data)

    change_to_parent_repo(src, parent)
    run_git_remote_commands(username, fork_path)


def get_parent_repo_data(data):
    parent_tmp = data["parent"]["full_name"].split("/")
    parent = {"user": parent_tmp[0], "repo": parent_tmp[1], "site": "github.com"}
    return parent


def change_to_parent_repo(src, parent):
    parent_dir = pathlib.Path(src, parent["site"], parent["user"], parent["repo"])

    # TODO Make this add the fork repo
    if not parent_dir.is_dir():

        print("The parent repo does not exist.")
        return

    os.chdir(parent_dir)


def run_git_remote_commands(username, fork_path):
    output = subprocess.run(
        ["git", "remote", "add", username, fork_path], capture_output=True
    )
    exit_on_subprocess_error(output)

    output = subprocess.run(["git", "remote"], capture_output=True)
    exit_on_subprocess_error(output)

    remotes = output.stdout.decode().split("\n")
    if username in remotes:
        print(f"New remote has been added: {username} :: {fork_path}")


def exit_on_subprocess_error(subprocess_output):
    if len(subprocess_output.stderr) > 0:
        print(subprocess_output.stderr.decode())
        exit(2)


def get_api_repo_data(username, repo):
    api = "https://api.github.com/repos"
    response = requests.get(f"{api}/{username}/{repo}")
    if response.status_code != 200:
        print("Error in connection to github.com api")
        return
    return response.json()


def get_username_and_repo(fork_path):
    username = None
    repo = None
    contents = parse_url_content(fork_path)
    site = contents["site"]
    # TODO This needs to fail out if the site is not github.com
    github = site["github.com"]
    if len(github.keys()) == 1:
        for key in github.keys():
            username = key

    if len(github[username].keys()) == 1:
        for key in github[username].keys():
            repo = key

    return username, repo


def version():
    ver = grab.__version__.split(" ")
    ver = ver[0]
    releases = get_releases()

    if ver not in releases:
        release = f"{grab.__version__} - Experimental Version"
    elif ver == releases[0]:
        release = f"{grab.__version__}"
    else:
        release = f"{grab.__version__} - Newer version is available"

    return release


def get_releases():
    response = requests.get("https://pypi.python.org/pypi/git-grab/json")
    data = response.json()
    releases = list(data["releases"].keys())
    releases = sorted(releases, reverse=True)
    return releases
