from nox_poetry import session

VERSIONS = ["3.8", "3.9", "3.10", "3.11"]

@session
def lint(session):
         session.install("flake8")
         session.run("flake8", "git_grab")


@session(python=VERSIONS)
def test(session):
    session.install("pytest", ".")
    session.run("pytest", "tests")
