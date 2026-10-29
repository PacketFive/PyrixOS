# Releasing

Each component is released from its own repository by pushing a version tag. The tag starts the `Release` workflow, which runs the quality gates on Python 3.12 and 3.13, builds the sdist and the wheel once, publishes them to PyPI through trusted publishing with PEP 740 attestations, and creates the GitHub release with a build provenance attestation and the notes from `CHANGELOG.md`.

| Repository | PyPI project | Depends on |
| --- | --- | --- |
| [pybonsai](https://github.com/PacketFive/pybonsai) | [`pybonsai-lang`](https://pypi.org/project/pybonsai-lang/) | Nothing |
| [cloche](https://github.com/PacketFive/cloche) | [`cloche`](https://pypi.org/project/cloche/) | Pydantic |
| [trellis](https://github.com/PacketFive/trellis) | [`trellis-kconfig`](https://pypi.org/project/trellis-kconfig/) | Pydantic |
| [lattice](https://github.com/PacketFive/lattice) | [`pyrixos-lattice`](https://pypi.org/project/pyrixos-lattice/) | The three above |

Release Lattice last, since its requirements name the others.

## Once per repository

1. On PyPI, under *Your projects*, *Publishing*, add a pending trusted publisher with the owner `PacketFive`, the repository name, the workflow `release.yml` and the environment `pypi`. The PyPI project is created by the first upload.
2. On GitHub, under *Settings*, *Environments*, create the environment `pypi`. Adding yourself as a required reviewer makes every upload wait for your approval.
3. Under *Settings*, *Branches*, protect `main` and require the `CI` checks to pass.

## Every release

1. Set `__version__` in `src/__init__.py`. Versions follow semantic versioning: a change that breaks a caller needs a new major version.
2. Add a section `## [X.Y.Z] - YYYY-MM-DD` to `CHANGELOG.md`. The workflow refuses a tag without one.
3. Commit, push, and wait for `CI` to pass on `main`.
4. Tag and push the tag:

    ```sh
    git tag -a vX.Y.Z -m "VERSION X.Y.Z"
    git push origin vX.Y.Z
    ```

5. Approve the `pypi` environment if it asks, and check the release on PyPI and GitHub.
6. In this repository, move the submodule to the tagged commit and commit the new pointer.

A tag that does not match `__version__` stops the workflow before anything is built. A version uploaded to PyPI cannot be uploaded again; fix a broken release with the next patch version.

## Checking a release

```sh
pip download --no-deps pybonsai-lang==X.Y.Z
gh attestation verify pybonsai_lang-X.Y.Z-py3-none-any.whl --repo PacketFive/pybonsai
```
