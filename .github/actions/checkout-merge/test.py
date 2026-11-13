"""Offline regression tests: python3 .github/actions/checkout-merge/test.py.

Requires PyYAML, Bash, Git, and jq. Executes the action's actual shell script
against temporary Git repositories and a stub GitHub API; never calls GitHub.
"""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml


ACTION = yaml.safe_load(Path(__file__).with_name("action.yml").read_text())
SCRIPT = ACTION["runs"]["steps"][0]["run"]


class CheckoutReviewedPR(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="checkout-reviewed-pr-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.remote = self.root / "remote"
        self.remote.mkdir()
        self.env = dict(os.environ)
        # Ignore developer Git settings, including signing and commit hooks.
        self.env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        self.git(self.remote, "init", "-q", "-b", "main")
        self.git(self.remote, "config", "user.name", "Test")
        self.git(self.remote, "config", "user.email", "test@example.invalid")
        self.initial = self.commit("shared", "initial")
        self.base = self.commit("base-only", "base change")
        self.git(self.remote, "checkout", "-q", "-b", "fork-head", self.initial)
        self.head = self.commit("head-only", "reviewed change")
        self.later = self.commit("later-only", "unreviewed change")
        # Expose the fork commit through the base repository's PR ref, as GitHub
        # does. No fork branch name or fork remote is needed to fetch it.
        self.git(self.remote, "update-ref", "refs/pull/1/head", self.head)
        self.git(self.remote, "checkout", "-q", "main")
        self.git(self.remote, "branch", "-D", "fork-head")
        self.checkout = self.root / "checkout"
        self.git(self.root, "clone", "-q", "--depth=1", "--branch=main",
                 self.remote.as_uri(), str(self.checkout))
        self.git(self.checkout, "checkout", "-q", "--detach")
        self.response = self.root / "response.json"
        self.set_response(self.base, self.head)
        self.api_log = self.root / "api-called"
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        gh = bin_dir / "gh"
        gh.write_text(
            "#!/usr/bin/env bash\nset -euo pipefail\n"
            '[[ "$*" == "api repos/test/repo/pulls/1" ]]\n'
            ': > "$TEST_API_LOG"\n'
            'if [ -n "${TEST_ADVANCE_SHA:-}" ]; then\n'
            '  git -C "$TEST_REMOTE" update-ref refs/pull/1/head "$TEST_ADVANCE_SHA"\n'
            'fi\n'
            'cat "$TEST_RESPONSE"\n'
        )
        gh.chmod(0o755)
        self.env.update(
            PATH=str(bin_dir) + os.pathsep + self.env["PATH"],
            TEST_API_LOG=str(self.api_log), TEST_REMOTE=str(self.remote),
            TEST_RESPONSE=str(self.response), REPO="test/repo", GH_TOKEN="",
        )

    def git(self, directory, *args):
        return subprocess.run(
            ["git", *args], cwd=directory, env=self.env,
            text=True, capture_output=True, check=True,
        ).stdout.strip()

    def commit(self, filename, contents):
        (self.remote / filename).write_text(contents + "\n")
        self.git(self.remote, "add", filename)
        self.git(self.remote, "commit", "-q", "-m", contents)
        return self.git(self.remote, "rev-parse", "HEAD")

    def set_response(self, base, head):
        self.response.write_text(json.dumps({"base": {"sha": base}, "head": {"sha": head}}))

    def execute(self, pr="1", head=None, **extra_env):
        env = dict(self.env, PR_NUMBER=pr,
                   REVIEWED_HEAD_SHA=self.head if head is None else head, **extra_env)
        return subprocess.run(
            ["bash", "-e", "-o", "pipefail", "-c", SCRIPT],
            cwd=self.checkout, env=env, text=True, capture_output=True,
        )

    def assert_reviewed_merge(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.checkout / "base-only").exists())
        self.assertTrue((self.checkout / "head-only").exists())
        self.assertFalse((self.checkout / "later-only").exists())
        self.assertEqual(self.git(self.checkout, "rev-parse", "HEAD^1"), self.base)
        self.assertEqual(self.git(self.checkout, "rev-parse", "HEAD^2"), self.head)

    def test_shallow_checkout_merges_reviewed_head_into_base(self):
        self.assert_reviewed_merge(self.execute())

    def test_full_checkout_and_uppercase_sha(self):
        self.git(self.checkout, "fetch", "--unshallow", "origin")
        self.assert_reviewed_merge(self.execute(head=self.head.upper()))

    def test_pr_moving_after_api_snapshot_does_not_change_tested_commit(self):
        self.assert_reviewed_merge(self.execute(TEST_ADVANCE_SHA=self.later))

    def test_stale_reviewed_sha_fails_before_checkout(self):
        self.set_response(self.base, self.later)
        result = self.execute()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PR head changed", result.stdout)
        self.assertEqual(self.git(self.checkout, "rev-parse", "HEAD"), self.base)

    def test_empty_inputs_keep_workflow_commit_without_api_call(self):
        result = self.execute(pr="", head="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git(self.checkout, "rev-parse", "HEAD"), self.base)
        self.assertFalse(self.api_log.exists())

    def test_invalid_or_unpaired_inputs_fail_before_api_call(self):
        for pr, head in [("1", ""), ("", self.head), ("0", self.head),
                         ("1; false", self.head), ("1", "main"),
                         ("1", self.head + "\nextra=value")]:
            with self.subTest(pr=pr, head=head):
                self.assertNotEqual(self.execute(pr=pr, head=head).returncode, 0)
                self.assertFalse(self.api_log.exists())

    def test_invalid_api_sha_fails_before_checkout(self):
        self.set_response("main", self.head)
        self.assertNotEqual(self.execute().returncode, 0)
        self.assertEqual(self.git(self.checkout, "rev-parse", "HEAD"), self.base)

    def test_missing_commit_fails_instead_of_using_branch_tip(self):
        missing = "a" * 40
        self.set_response(self.base, missing)
        self.assertNotEqual(self.execute(head=missing).returncode, 0)
        self.assertEqual(self.git(self.checkout, "rev-parse", "HEAD"), self.base)

    def test_merge_conflict_fails_instead_of_testing_head_alone(self):
        self.base = self.commit("shared", "base edit")
        self.git(self.remote, "checkout", "-q", "--detach", self.head)
        self.head = self.commit("shared", "head edit")
        self.git(self.remote, "update-ref", "refs/pull/1/head", self.head)
        self.git(self.remote, "checkout", "-q", "main")
        self.set_response(self.base, self.head)
        self.assertNotEqual(self.execute().returncode, 0)
        self.assertTrue(self.git(self.checkout, "diff", "--name-only", "--diff-filter=U"))


if __name__ == "__main__":
    unittest.main()
