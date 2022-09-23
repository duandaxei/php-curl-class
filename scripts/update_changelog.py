import os
import pprint
from copy import copy
from datetime import datetime, timezone
from pathlib import Path

import git
from github import Github


# The owner and repository name. For example, octocat/Hello-World.
GITHUB_REPOSITORY = os.getenv('GITHUB_REPOSITORY')

GITHUB_TOKEN = os.getenv('GITHUB_TOKEN')
PRODUCTION = os.getenv('PRODUCTION', False)

CURRENT_FILE = Path(__file__)
ROOT = CURRENT_FILE.parents[1]
CHANGELOG_PATH = ROOT / 'CHANGELOG.md'

# TODO: Adjust number of recent pull requests to include likely number of
# pull requests since the last release.
RECENT_PULL_REQUEST_LIMIT = 10


def main():
    # Find most recent tag and timestamp.
    #   git for-each-ref --format="%(refname:short) | %(creatordate)" "refs/tags/*"
    local_repo = git.Repo(ROOT)

    # Fetch tags since `git fetch' is run with --no-tags during actions/checkout.
    #   git fetch --tags
    for remote in local_repo.remotes:
        remote.fetch()

    tags = sorted(local_repo.tags, key=lambda tag: tag.commit.committed_datetime)
    most_recent_tag = tags[-1]

    print('most_recent_tag: {}'.format(most_recent_tag))
    most_recent_tag_datetime = most_recent_tag.commit.committed_datetime
    print('most_recent_tag_datetime: {}'.format(most_recent_tag_datetime))

    # Find merged pull requests since the most recent tag.
    github_repo = Github(login_or_token=GITHUB_TOKEN).get_repo(GITHUB_REPOSITORY)
    recent_pulls = github_repo.get_pulls(
        state='closed',
        sort='updated',
        direction='desc',
    )[:RECENT_PULL_REQUEST_LIMIT]

    pull_request_changes = []
    for pull in recent_pulls:
        # print('-' * 10)

        if not pull.merged:
            # print('skipping since not merged: {}'.format(pull.title))
            # print(pull.html_url)
            continue

        # Make merged_at timestamp offset-aware. Without this, the following
        # error will appear:
        #   TypeError: can't compare offset-naive and offset-aware datetimes
        pull_merged_at = copy(pull.merged_at).replace(tzinfo=timezone.utc)

        if pull_merged_at < most_recent_tag_datetime:
            # print('skipping since merged prior to last release: {}'.format(pull.title))
            # print(pull.html_url)
            continue

        # pprint.pprint(dir(pull))
        pprint.pprint(pull.title)
        pprint.pprint('most recent: {}'.format(most_recent_tag_datetime))
        pprint.pprint('merged at:   {}'.format(pull.merged_at))
        print(pull.html_url)

        pull_request_changes.append(
            '- {} ([#{}]({}))'.format(pull.title, pull.number, pull.html_url)
        )

        print('-' * 10)

    pprint.pprint(pull_request_changes)

    # TODO: Fetch next actual semantic version.
    release_version = most_recent_tag
    release_date = datetime.today().strftime('%Y-%m-%d')
    release_title = '{} - {}'.format(release_version, release_date)
    print('release_title: {}'.format(release_title))

    release_content = (
        '## {}\n'
        '\n'
        '{}'
    ).format(release_title, '\n'.join(pull_request_changes))

    old_content = CHANGELOG_PATH.read_text()
    new_content = old_content.replace(
        '<!-- CHANGELOG_PLACEHOLDER -->',
        '<!-- CHANGELOG_PLACEHOLDER -->\n\n{}'.format(release_content),
    )
    print(new_content[:800])
    # CHANGELOG_PATH.write_text(new_content)


if __name__ == '__main__':
    main()
