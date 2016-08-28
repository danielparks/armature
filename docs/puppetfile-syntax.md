# Puppetfile syntax

The Puppetfile is just ruby. Armature provides one important function:

### `mod 'name', :git=>'url', :ref=>'ref'`
Specifies a module to install.

* **name:** The name of the module. You use this in your Puppet code to
  reference the module's classes and defined types.
* **url:** The URL of the git repo holding the module.
* **ref:** The ref in the repo to check out. May be a branch, a tag, or a sha.
  Defaults to "master".

## Example

~~~ ruby
mod 'autosign',
  :git => 'git://github.com/danieldreier/puppet-autosign.git',

mod 'aws',
  :git => 'git://github.com/puppetlabs/puppetlabs-aws.git',
  :ref => '1.4.0'
~~~

## Compatibility

Armature does not support the full syntax of either
[r10k](https://github.com/puppetlabs/r10k/blob/master/doc/puppetfile.mkd) or
[librarian-puppet](http://librarian-puppet.com). It will likely support more of
r10k's syntax at some point.

It does provide a `forge` function which accepts any arguments and is ignored.
This is only for compatility with the Puppetfile I'm using.
