import pathlib
import os
import subprocess
from pprint import pprint

import click
import tinydb
from typing import List
from tabulate import tabulate

from dataclasses import dataclass, field, asdict

from pony.orm import select, db_session, commit

from grab.model import setup_db_connection, Repo

__all__ = [
    "Card",
    "set_db_path",
    "get_db_path",
    "add_card",
    "get_card",
    "list_cards",
    "count",
    "update_card",
    "delete_card",
    "delete_all",
    "update_repos",
    "update_repo",
    "add_repos",
    "list_repos",
    "remove_repo",
    "remove_all_repos",
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


def update_repo(name):
    """Update all the repos in the system"""
    print(f"Update repo {name}")


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
    print(f"Removing a repo: {name}")


def remove_all_repos():
    """Remove a repo from the system defaults to one"""
    x = 1

    while x < 11:

        print(f"Removing a repo: {x}")
        x += 1


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
        data = [parse_ssh_line(url)]
        return compile_line_data(data)

    else:
        print(f"URL is wrong format \n ==> '{url}'")

    return None


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


def stash_changes_and_checkout_master():
    output = subprocess.run(["git", "status", "-s"], capture_output=True)
    past_branch = get_branch_name()
    if len(output.stdout) > 0:
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


def get_branch_name():
    """
    This expects to be in git repo.
    :return: branch name
    """
    branch = subprocess.run(["git", "branch"], capture_output=True)
    stdout = branch.stdout.decode()
    split = stdout.split("\n")
    output = None
    for branch in split:
        print(branch)
        if branch.startswith("* "):
            branch = branch.split("* ")
            output = branch[1]

    return output


def is_on_branch(branch="master"):
    """
    This expects to be in git repo.
    :return: True if on master branch
    """
    status = subprocess.run(["git", "branch"], capture_output=True)
    stdout = status.stdout.decode()
    split = stdout.split("\n")
    for entry in split:
        if entry.startswith("* "):
            if entry.endswith(branch):
                return True
            else:
                return False


@db_session
def get_repo_paths_from_db():
    return select(r.path for r in Repo)[:]


@dataclass
class Card:
    summary: str = None
    owner: str = None
    priority: int = None
    done: bool = None
    id: int = field(default=None, compare=False)

    @classmethod
    def from_dict(cls, d):
        return Card(**d)

    def to_dict(self):
        return asdict(self)


_db = None
_db_path = None


def set_db_path(db_path=None):
    global _db
    global _db_path
    if db_path is None:
        _db_path = pathlib.Path().home() / ".cards_db.json"
    else:
        _db_path = db_path
    _db = tinydb.TinyDB(_db_path)


def get_db_path():
    return _db_path


def add_card(card: Card) -> int:
    """Add a card, return the id of card."""
    card.id = _db.insert(card.to_dict())
    _db.update(card.to_dict(), doc_ids=[card.id])
    return card.id


def get_card(card_id: int) -> Card:
    """Return a card with a matching id."""
    return Card.from_dict(_db.get(doc_id=card_id))


def list_cards(filter=None) -> List[Card]:
    """Return a list of all grab."""
    q = tinydb.Query()
    if filter:
        noowner = filter.get("noowner", None)
        owner = filter.get("owner", None)
        priority = filter.get("priority", None)
        done = filter.get("done", None)
    else:
        noowner = None
        owner = None
        priority = None
        done = None
    if noowner and owner:
        results = _db.search(
            (q.owner == owner)
            | (q.owner == None)
            | (q.owner == "")  # noqa : "is None" doesn't work for TinyDb
        )
    elif noowner or owner == "":
        results = _db.search((q.owner == None) | (q.owner == ""))  # noqa
    elif owner:
        results = _db.search(q.owner == owner)
    elif priority:
        results = _db.search((q.priority != None) & (q.priority <= priority))  # noqa
    else:
        results = _db

    if done is None:
        # return all grab
        return [Card.from_dict(t) for t in results]
    elif done:
        # only done grab
        return [Card.from_dict(t) for t in results if t["done"]]
    else:
        # only not done grab
        return [Card.from_dict(t) for t in results if not t["done"]]


def count(noowner=None, owner=None, priority=None, done=None) -> int:
    """Return the number of grab in db."""
    filter = {"noowner": noowner, "owner": owner, "priority": priority, "done": done}
    return len(list_cards(filter=filter))


def update_card(card_id: int, card_mods: Card) -> None:
    """Update a card with modifications."""
    d = card_mods.to_dict()
    changes = {k: v for k, v in d.items() if v is not None}
    _db.update(changes, doc_ids=[card_id])


def delete_card(card_id: int) -> None:
    """Remove a card from db with given card_id."""
    _db.remove(doc_ids=[card_id])


def delete_all() -> None:
    """Remove all tasks from db."""
    _db.purge()
