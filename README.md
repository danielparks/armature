# Armature

A tool for deploying Puppet environments and modules.

~~~
$ armature deploy-branches my-puppet-code.git '*'
~~~

Armature sets up Puppet environments for each branch in your control repo and
installs modules as specified by the Puppetfile for each environment.

Armature is designed to replace [r10k][] for certain, very specific use cases.
It does not have nearly as many features, but it is _much_ faster.

## Development status

This is mostly abandoned and I am unlikely to do much more work on this. For
most people [r10k][] is fast enough.

## Glossary

* **Control repository (or repo):** The main git repository containing your
  Puppet code.
* **Puppetfile:** A file listing modules needed by the Puppet code in your
  control repo. See the [syntax documentation](docs/puppetfile-syntax.md).
* **Environment:** A directory containing Puppet code and resources. The master
  can serve different environments to different nodes.

  For example, you might have a dev environment that contains Puppet code in
  development, and a prod environment that runs on the production nodes. See
  the [official Puppet documentation.
  ](https://puppet.com/docs/puppet/latest/environments_about.html)

## Usage

There are three commands you need to use. Run `armature help` to learn about
options, or `armature help <command>` to learn about a specific command.

### `armature deploy-branches <git-url> <branch>`

Deploys branches from a git repository as environments.

### `armature deploy-puppetfile`

Deploys the Puppetfile in the current directory into `./modules`.

### `armature update`

Updates all branches in the cache. This will update all environments to their
latest commit in git, as well as all modules that were specified with a branch
ref (this will not update tags).

### `armature gc`

Removes unused objects from the cache. For example, old commits in the control
repo that are no longer used as environments.

[r10k]: https://github.com/puppetlabs/r10k
