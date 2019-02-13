# Puppetfile syntax

The Puppetfile is just ruby. There are a few important declarations:

### `mod 'owner-name', 'version'`

Install a module from the Forge. This will use whatever “forge” was last set
with the `forge` function.

* **owner-name:** This is the name of the Forge user and the name of the
  module. The module name is what's used in your Puppet code.
* **version:** The version of the module to install. If you don't specify a
  version, or use `:latest`, this will check the Forge for the latest version
  of the module every time this environment is deployed.

This uses the same syntax as suggested by the Forge.

### `mod 'name', :git=>'url', :tag=>'tag'`

Install a module with git.

* **name:** The name of the module. You use this in your Puppet code to
  reference the module's classes and defined types.
* **url:** The URL of the git repo holding the module.

You may optionally use one of the following parameters. If you don't specify
one, it will default to the master branch.

* `:tag => 'tag'` This assumes that the tag will never change.
* `:branch => 'branch'` This will check for updates to the branch on every
  deploy.
* `:commit => 'SHA'`

You can also use `:ref` to specify any of the above, or another type of git
ref. Using this will cause armature to check for updates on every deploy.

### `forge 'https://forge.puppet.com'`

This specifies what “forge” to use. You don't need to specify this unless you
have a caching proxy, or your own Forge-like web site.

### `moduledir 'modules'`

What directory should the modules go in? You should almost never need to
specify this.

## Example

~~~ ruby
mod 'puppetlabs-ntp', '7.3.0'
mod 'puppetlabs-stdlib'

mod 'autosign',
  :git    => 'git://github.com/danieldreier/puppet-autosign.git',
  :commit => '0e1367db3fe43a62b38d96a373db8b465cb8fdb3'

mod 'aws',
  :git => 'git://github.com/puppetlabs/puppetlabs-aws.git',
  :tag => '1.4.0'
~~~

## Compatibility

Armature does not support the full syntax of either
[r10k](https://github.com/puppetlabs/r10k/blob/master/doc/puppetfile.mkd) or
[librarian-puppet](http://librarian-puppet.com). Submit an
[issue](https://github.com/danielparks/armature/issues) if you have a specific
feature you need.
