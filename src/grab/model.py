import pathlib

from pony.orm import *


db = Database()


class Repo(db.Entity):
    id = PrimaryKey(int, auto=True)
    name = Required(str)
    path = Required(str)
    clone = Required(str, unique=True)


def setup_db_connection():
    path = check_config_path_exists()
    filename = pathlib.Path(path, "repos")
    filename = str(filename)
    db.bind(provider="sqlite", filename=filename, create_db=True)
    db.generate_mapping(create_tables=True)


def check_config_path_exists():
    host = pathlib.Path.home()
    config = pathlib.Path(host, ".config", "grab")

    if not config.is_dir():
        config.mkdir(parents=True)

    return str(config)
