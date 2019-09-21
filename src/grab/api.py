import pathlib
import tinydb
from typing import List

from dataclasses import dataclass, field, asdict


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


def update_repos():
    """Update all the repos in the system"""
    print("Update all the repos")

def update_repo(name):
    """Update all the repos in the system"""
    print(f"Update repo {name}")


def add_repos(file_name, url, base_path):

    if file_name:
        add_repos_from_file(file_name, base_path)
    elif url:
        add_repo_from_url(url, base_path)
    else:
        raise RuntimeError("You should not have gotten this far")


def add_repos_from_file(file_path, base_path):
    """Add repos from a file"""
    print("create repos from a file")


def add_repo_from_url(url, base_path):
    """Add repos from a file"""
    print("create repo from a URL")


def list_repos(detail):
    """List all the repos in the system"""
    print("List all the repos")
    if detail:
        print("There is more detail been printed")


def remove_repo(name):
    """Remove a repo from the system defaults to one"""
    print(f"Removing a repo: {name}")


def remove_all_repos():
    """Remove a repo from the system defaults to one"""
    x = 1

    while x < 11:

        print(f"Removing a repo: {x}")
        x += 1


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
