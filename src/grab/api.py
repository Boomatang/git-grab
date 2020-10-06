import pathlib
import os
import shutil
import subprocess
import time
import json
from pprint import pprint

import requests
import click
from typing import List
from tabulate import tabulate

from dataclasses import dataclass, asdict

import grab
from grab.helper import is_on_branch, get_branch_name

__all__ = [
    "add_repos",
    "fork",
    "version",
    "generate",
    "show_paths",
    "list_repos",
    "path_to_repo",
]

HOST = pathlib.Path.home()
CONFIG_FOLDER = pathlib.Path(HOST, ".config", "grab")
GRAB_PATH_LOCATION = pathlib.Path(CONFIG_FOLDER, "paths.json")
GRAB_REPOS_LOCATION = pathlib.Path(CONFIG_FOLDER, "repos.json")


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


def add_repos(file_name, url, base_path):
    base_path_check(base_path)

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


def get_repo_names():
    return []


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
    data = SshInfo()
    data.site = site
    data.user = user
    data.repo = repo
    data.ssh = http
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
    data = SshInfo()
    data.site = site
    data.user = user
    data.repo = repo
    data.ssh = ssh
    return data


def process_contents(contents, base_path):
    folders, folders_and_ssh = create_required_folders(contents, base_path)
    create_user_folders(folders)
    errors = clone_git_repos(folders_and_ssh)

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
    # response = requests.get("https://pypi.python.org/pypi/git-grab/json")
    # data = response.json()
    # releases = list(data["releases"].keys())
    # releases = sorted(releases, reverse=True)
    # return releases
    return grab.__releases__


def generate(grab_path, paths, new_file):
    locations = create_paths_file(new_file, grab_path, paths)

    print("Paths been scanned:\n\t", end="")
    print("\n\t".join(locations))
    repos = find_repos_in_locations(locations)
    create_repos_file(repos)


def create_repos_file(repos):
    data = get_raw_data(repos)
    print(f"{len(data)} repos found")
    orgs = sorted_orgs(data)
    group_repos = grouped_repos(orgs, data)
    final = sorted_repos_list(orgs, group_repos, data)
    result = {"repos": final, "orgs": orgs}
    GRAB_REPOS_LOCATION.write_text(json.dumps(result, indent=2, sort_keys=True))


def find_repos_in_locations(locations):
    repos = []
    hold = None
    for path in locations:
        for current, b, c in os.walk(path):
            if hold is not None and current.startswith(hold):
                continue

            if is_git_directory(current):
                repos.append(current)
                hold = current
    return repos


def get_raw_data(repos):
    data = []
    for repo in repos:
        data.append(build_repo_object(repo))
    return data


def sorted_orgs(data):
    orgs = []
    for point in data:
        if point["org"] not in orgs:
            orgs.append(point["org"])
    orgs = sorted(orgs)
    return orgs


def grouped_repos(orgs, data):
    group_repos = {}
    for org in orgs:
        group_repos.setdefault(org, [])

        for point in data:
            if point["org"] == org:
                group_repos[org].append(point["repo"])
        group_repos[org] = sorted(group_repos[org])
    return group_repos


def sorted_repos_list(orgs, group_repos, data):
    final = []
    index = 1
    # I know this is really bad for loop
    for org in orgs:
        for repo in group_repos[org]:
            for point in data:
                if point["repo"] == repo and point["org"] == org:
                    point["index"] = index
                    index += 1
                    point["display"] = f"{point['org']}/{point['repo']}"
                    final.append(point)
    return final


def build_repo_object(repo):
    repo = pathlib.Path(repo)
    name = repo.parts[-1]
    org = repo.parts[-2]
    site = repo.parts[-3]
    return {"repo": name, "org": org, "site": site, "location": str(repo)}


def create_paths_file(new_file, grab_path, paths):
    locations = []
    if garb_paths_file_exists() and not new_file:
        print("reading paths from existing")
        locations = get_existing_locations()
    else:
        # Blank out the existing file
        GRAB_PATH_LOCATION.write_text("")

    check_locations(grab_path, paths, locations)
    locations = sorted(locations)
    dict_file = {"created": time.strftime("%l:%M%p %z %d/%m/%Y"), "dirs": locations}
    GRAB_PATH_LOCATION.write_text(json.dumps(dict_file))

    return locations


def get_existing_locations():
    with open(str(GRAB_PATH_LOCATION), "r") as file:
        data = json.load(file)
    return data["dirs"]


def check_locations(grab_path, paths, locations):
    if not path_exists(grab_path):
        print(
            "Environment Variable GRAB_PATH to does not point to an real location, Skipping..."
        )
    else:
        if grab_path not in locations:
            locations.append(grab_path)

    for path in paths:
        if not path_exists(path):
            print(f"{path} is not a real location, Skipping...")
        else:
            if path not in locations:
                locations.append(path)


def path_exists(path):
    path = pathlib.Path(path)
    if path.is_dir():
        return True
    else:
        return False


def garb_paths_file_exists():
    return GRAB_PATH_LOCATION.is_file()


def is_git_directory(path="."):
    return (
        subprocess.call(
            ["git", "-C", path, "status"],
            stderr=subprocess.STDOUT,
            stdout=open(os.devnull, "w"),
        )
        == 0
    )


def show_paths():
    with open(GRAB_PATH_LOCATION, "r") as paths:
        data = json.load(paths)

    for dir in data["dirs"]:
        print(dir)


def list_repos(org=None, wide=False):
    if not file_exists(GRAB_REPOS_LOCATION):
        print("No repos file exists, run grab list --generate to create this file.")
        print("Aborting...")
        exit(1)
    with open(GRAB_REPOS_LOCATION, "r") as paths:
        data = json.load(paths)

    if org is not None:
        data = filtered_data(org, data)
    if wide:
        print(wide_list(data))
    else:
        print(narrow_list(data))


def filtered_data(org: str, data):
    key = [a for a in data["orgs"] if a.lower() == org.lower()]
    if len(key) <= 0:
        print(f"No information found for {org}")
        print("Aborting...")
        exit(1)

    key = key[0]
    result = []
    for repo in data["repos"]:
        if repo["org"] == key:
            result.append(repo)
    return {"repos": result}


def file_exists(path_to_file: pathlib.Path):
    return path_to_file.is_file()


def narrow_list(data):
    header = ["#", "Org/Repo"]
    result_data = []
    for entry in data["repos"]:
        result_data.append((entry["index"], entry["display"]))

    table = tabulate(result_data, header)
    return table


def wide_list(data):
    header = ["#", "Org/Repo", "Location", "Site"]
    result_data = []
    for entry in data["repos"]:
        result_data.append(
            (entry["index"], entry["display"], entry["location"], entry["site"])
        )

    table = tabulate(result_data, header)
    return table


def path_to_repo(repo):
    if is_number(repo):
        path = get_path(id=int(repo))
    elif is_url(repo):
        org_project = split_url_to_org_project(repo)
        path = get_path(path=org_project)
    else:
        path = get_path(path=repo)

    print(path)


def split_url_to_org_project(repo: str):
    split = repo.split("://")
    split = split[1].split("/")
    output = "/".join([split[1], split[2]])
    return output


def is_url(repo: str):
    if repo.lower().startswith("http://") or repo.lower().startswith("https://"):
        return True
    else:
        return False


def is_number(value):
    try:
        test = int(value)
        return True
    except:
        return False


def get_path(id=None, path=None):
    records = load_records()
    result = None

    if id:
        for record in records:
            if record["index"] == id:
                result = record["location"]
                break

    if path:
        for record in records:
            if record["display"].lower() == path.lower():
                result = record["location"]
                break

    if result is None:
        return f'No Repo entry found for "{path}"'
    return result


def load_records():
    with open(GRAB_REPOS_LOCATION, "r") as paths:
        output = json.load(paths)
    return output["repos"]
