import argparse
import logging
import os
import subprocess  # nosec
import tempfile
from pathlib import Path
from urllib.parse import ParseResult, urlparse

logger = logging.getLogger("grab")


class Repository:
    site: str
    owner: str
    project: str
    clone: str

    def __init__(self, repo):
        logger.debug(f"Repository: {repo}")
        parsed = urlparse(repo)
        if len(parsed.scheme) == 0:
            self.git_parser(repo)
        else:
            self.url_parser(parsed)
        self.clone = repo

    def url_parser(self, parse: ParseResult):
        logger.debug(f"Url parser: {parse}")
        # https://github.com/Boomatang/git-grab.git
        self.site = parse.hostname
        string = parse.path.split("/")
        self.owner = string[1]
        string = string[2].split(".")
        self.project = string[0]

    def git_parser(self, parse: str):
        logger.debug(f"Git parser: {parse}")
        # git@github.com:Boomatang/git-grab.git
        parse = parse.split("@")
        parse = parse[1].split(":")
        self.site = parse[0]
        parse = parse[1].split("/")
        self.owner = parse[0]
        parse = parse[1].split(".")
        self.project = parse[0]

    def __repr__(self):
        return f"{self.site}/{self.owner}/{self.project}"


def configure_logger(logger, debug=False):
    ch = logging.StreamHandler()
    if debug:
        logger.setLevel(logging.DEBUG)
        ch.setLevel(logging.DEBUG)
    else:
        logger.setLevel(logging.INFO)
        ch.setLevel(logging.INFO)
    formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
    ch.setFormatter(formatter)
    logger.addHandler(ch)


def create_owner_path(path: Path, repo: Repository):
    p = Path(path, repo.site, repo.owner)
    logger.debug(f"Creating owner path: {p}, if not already exists")
    p.mkdir(parents=True, exist_ok=True)
    return p


def clone(path: Path, repo: Repository):
    logger.info(f"Starting to clone {repo}")
    value = subprocess.run(
        ["git", "-C", str(path), "clone", repo.clone], capture_output=True
    )  # nosec
    if value.returncode != 0:
        logger.error(f"Failed to clone {repo}")
        logger.debug(f"error: {value.stderr.decode()}")
    else:
        logger.info(f"Successfully cloned {repo}")


def wip():
    parser = argparse.ArgumentParser(
        prog="grab",
        description="grab clones the give repositories into a structure "
        "directory. The path to the root of this structure is "
        "set in the GRAB_PATH environment variable.",
    )
    parser.add_argument(
        "REPOS",
        nargs="*",
        help="Git repositories to clone.",
    )
    parser.add_argument(
        "-p",
        "--path",
        help="Overrides the path set in the GRAB_PATH environment variable.",
    )
    parser.add_argument(
        "-t",
        "--temp",
        help="Download repositories to a temporary directory. This will be the OS "
        "default temporary directory.",
        action="store_true",
    )
    parser.add_argument(
        "-f", "--fork", help="Add fork to existing repo.", action="store_true"
    )
    parser.add_argument("--debug", help="Enable debug mode.", action="store_true")
    args = parser.parse_args()
    configure_logger(logger, debug=args.debug)

    logger.debug(f"{args=}")

    if args.temp and args.path is not None:
        logger.error("Cannot specify both --temp and --path.")
        exit(1)

    if args.temp:
        path = tempfile.gettempdir()
        logger.debug(f"Using temp directory {path}")
    elif args.path:
        path = args.path
        logger.debug(f"Using path {path}")
    else:
        path = os.getenv("GRAB_PATH", None)
        logger.debug(f"Using default path {path}")

        if path is None:
            logger.error("No path provided.")
            logger.info("Set GRAB_PATH environment variable or use --path.")
            exit(1)

    path = Path(path)
    if not path.is_dir():
        logger.error(f'Path "{path}" not a directory.')
        logger.info(f"Please create the directory: {path}")
        exit(1)

    for repo in args.REPOS:
        logger.info(f"Processing repository {repo}")
        r = Repository(repo)
        owner_path = create_owner_path(path, r)
        project_path = Path(owner_path, r.project)

        if project_path.is_dir():
            logger.warning(f'Directory "{project_path}" already exists.')
            logger.warning(f'Not attempting to clone "{repo}".')
            continue

        clone(owner_path, r)


if __name__ == "__main__":
    wip()
