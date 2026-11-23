# Policyfile: the modern way to say "servers running myapp get EXACTLY these
# cookbook versions and this run list". `cinc install` resolves it into
# myapp.lock.json (commit that file). The same lock is then pushed to the
# policy groups dev -> uat -> prod, so every environment runs identical code.
name 'myapp'

default_source :supermarket

run_list 'myapp::default'

# Our own cookbooks, straight from this repo.
cookbook 'myapp', path: '../cookbooks/myapp'
cookbook 'base',  path: '../cookbooks/base'

# ---- Site-specific settings (keep cookbooks generic, put site data here) ----

# Public key of the Jenkins deploy key pair (walkthrough Part 4). Public = not secret.
default['base']['deploy_user']['authorized_keys'] = [
  'REPLACE-ME: paste the contents of ~/chef-lab-keys/jenkins_deploy.pub',
]

# Per-environment values. Attributes under a key named after the policy group
# are "hoisted" onto nodes in that group: app03 (prod) sees log_level WARN.
default['dev']['myapp']['greeting']  = 'Hello from DEV'
default['dev']['myapp']['log_level'] = 'DEBUG'
default['uat']['myapp']['greeting']  = 'Hello from UAT'
default['prod']['myapp']['greeting'] = 'Hello from PROD'
default['prod']['myapp']['log_level'] = 'WARN'
