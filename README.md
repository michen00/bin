# bin

[![Build Status](https://img.shields.io/github/actions/workflow/status/michen00/bin/ci.yml?style=plastic)](https://github.com/michen00/bin/actions)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=plastic)](CONTRIBUTING.md)
[![License](https://img.shields.io/github/license/michen00/bin?style=plastic)](LICENSE)

This is a collection of scripts that I use to automate my workflow. I wrote them to make my life easier, and I hope they can help you, too.

## Quick Start

Clone the repository:

```sh
git clone git@github.com:michen00/bin.git
```

Copy its contents to your `bin` directory:

```sh
cp -r ./bin/* ~/bin
```

Alternatively, you can create a symbolic link to the `bin` directory:

```sh
ln -s ./bin ~/bin
```

Add the `bin` directory to your `PATH`

```sh
export PATH="$HOME/bin:$PATH"
```

Add the above line to your favorite shell configuration file (e.g. `~/.bashrc`, `~/bash_profile`, etc.; it might already be there) and `source` it. For example, for zsh:

```sh
. ~/.zshrc
```

## Scripts

- [`ach`](ach): Add the last commit hash to a given file (`.git-blame-ignore-revs` file by default).
- [`chdirx`](chdirx): Add `+x` permission to all executable files (that start with `#!`) in the given directory.
- [`gcfixup`](gcfixup): Create a fixup commit and automatically rebase with autosquash.
- [`git-shed`](git-shed): Identify and remove merged & stale branches with respect to a target branch.
- [`how-big`](how-big): Show the size of the given directory.
- [`mergewith`](mergewith): Merge the latest changes from a reference branch into the current branch (updating both).
- [`touchx`](touchx): Create (or update) a file and add `+x` permission to it.
- [`update-mine`](update-mine): Update all branches with open pull requests authored by you.
- [`venv-now`](venv-now): Create a new Python virtual environment in ./.venv (or the given directory), activating it if sourced.

## Documentation: [![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/michen00/bin)
