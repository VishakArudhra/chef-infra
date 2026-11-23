name             'myapp'
maintainer       'Shruthi'
maintainer_email 'you@example.com'
license          'Apache-2.0'
description      'Deploys the myapp Spring Boot service (Java + systemd) on top of the base cookbook'
version          '1.0.0'
chef_version     '>= 18.0'

supports 'ubuntu', '>= 22.04'

# Dependency with a version constraint. This is exactly the kind of "pin" that
# bit Vishak in UAT: keep constraints deliberate and reviewed.
depends 'base', '~> 1.0'
