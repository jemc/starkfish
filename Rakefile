require 'rake/testtask'
require 'rdoc/task'

gemname = 'starkfish'

# Rebuild gem
task :g do exec "
rm #{gemname}*.gem
gem build #{gemname}.gemspec
gem install #{gemname}*.gem" end

# Rebuild and push gem
task :gp do exec "
rm #{gemname}*.gem
gem build #{gemname}.gemspec
gem install #{gemname}*.gem
gem push #{gemname}*.gem" end
