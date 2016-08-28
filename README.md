# Gofer

A tool for deploying Puppet environments and modules.

~~~
$ gofer deploy-branch my-puppet-code.git '*'
~~~

Gofer sets up Puppet environments for each branch in your control repo and
installs modules as specified by the Puppetfile for each environment.

Gofer is designed to replace [r10k](https://github.com/puppetlabs/r10k) for
certain, very specific use cases. It does not have nearly as many features, but
it is _much_ faster.

_This is an alpha release. The interface is likely to change significantly._

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
  ](https://docs.puppet.com/puppet/latest/reference/environments.html)

## Usage

There are three commands you need to use. Run `gofer help` to learn about
options, or `gofer help <command>` to learn about a specific command.

### `gofer deploy-branch <git-url> <branch>`

Deploys branches from a git repository as environments.

### `gofer update`

Updates all branches in the cache. This will update all environments to their
latest commit in git, as well as all modules that were specified with a branch
ref (this will not update tags).

### `gofer gc`

Removes unused objects from the cache. For example, old commits in the control
repo that are no longer used as environments.
