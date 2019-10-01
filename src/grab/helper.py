import subprocess


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
        if branch.startswith("* "):
            branch = branch.split("* ")
            output = branch[1]

    return output
