# ChefSpec = fast unit tests. Nothing is installed: Chef compiles the recipe and
# we assert on the resources it WOULD manage. Run: cinc exec rspec
require 'chefspec'

RSpec.configure do |config|
  # Both cookbooks live side by side in ../../ so `depends 'base'` resolves.
  config.cookbook_path = [File.expand_path('../..', __dir__)]
  config.platform = 'ubuntu'
  config.version = '24.04'
  config.log_level = :error
end
