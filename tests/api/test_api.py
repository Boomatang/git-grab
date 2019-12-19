import subprocess

import grab
import grab.helper
import pytest


# CompletedProcess(args=['git', 'branch'], returncode=0, stdout=b'* master\n', stderr=b'')


class MockResponse:
    args = ["git", "branch"]
    returncode = 0
    stdout = b"* master\n"
    stderr = b""


@pytest.fixture
def mock_response(monkeypatch):
    def mockreturn(*args, **kwargs):

        return MockResponse()

    monkeypatch.setattr(subprocess, "run", mockreturn)


def test_is_on_branch(mock_response):
    assert grab.helper.is_on_branch() is True


def test_is_on_branch_not_dev_branch(mock_response):
    assert grab.helper.is_on_branch("dev") is False


@pytest.mark.parametrize("branch", [("master", True), ("dev", False)])
def test_get_branch_name(branch, mock_response):
    name = grab.helper.get_branch_name()
    # print(name)
    assert (name == branch[0]) == branch[1]


def test_update_repo(capsys):
    grab.update_repo("Sample")

    captured = capsys.readouterr()

    assert captured.out == "Update repo Sample\n"


def test_parse_line_contents_SSH_type():
    sample = "git@github.com:Sample/Repo.git"

    result = grab.api.parse_line_contents(sample)

    assert type(result) == grab.api.SshInfo
    assert result.repo == "Repo"
    assert result.user == "Sample"
    assert result.ssh == "git@github.com:Sample/Repo.git"
    assert result.site == "github.com"


def test_parse_line_contents_HTTPS_type(capsys):
    sample = "https://github.com/Sample/Repo.git"

    result = grab.api.parse_line_contents(sample)

    captured = capsys.readouterr()

    assert (
        captured.out
        == "File line is wrong format \n ==> 'https://github.com/Sample/Repo.git'\n"
    )
    assert result is None


def test_parse_line_contents_not_valid_type(capsys):
    sample = "Not Valid URL type"

    result = grab.api.parse_line_contents(sample)

    captured = capsys.readouterr()

    assert captured.out == "File line is wrong format \n ==> 'Not Valid URL type'\n"
    assert result is None


def test_parse_url_content_SSH_type():
    sample = "git@github.com:Sample/Repo.git"
    expected = {
        "site": {"github.com": {"Sample": {"Repo": "git@github.com:Sample/Repo.git"}}}
    }

    result = grab.api.parse_url_content(sample)

    assert result == expected


def test_parse_url_content_HTTPS_type(capsys):
    sample = "repo=https://github.com/Sample/Repo.git"

    result = grab.api.parse_url_content(sample)

    captured = capsys.readouterr()

    assert (
        captured.out
        == "URL is wrong format \n ==> 'repo=https://github.com/Sample/Repo.git'\n"
    )
    assert result is None


def test_parse_url_content_not_valid_type(capsys):
    sample = "Not Valid URL type"

    result = grab.api.parse_url_content(sample)

    captured = capsys.readouterr()

    assert captured.out == "URL is wrong format \n ==> 'Not Valid URL type'\n"
    assert result is None
