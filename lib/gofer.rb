### Should gofer determine which refs it needs centrally, and then run on each compiler?
### Should the compilers git clone repos from the central authority?
### rsync instead? Is that faster?


require "gofer/cache.rb"
require "gofer/environments.rb"
require "gofer/gitrepo.rb"
require "gofer/puppetfile.rb"
require "gofer/run.rb"
require "gofer/util.rb"

module Gofer
end
