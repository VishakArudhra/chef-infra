default['myapp']['user']         = 'myapp'
default['myapp']['install_dir']  = '/opt/myapp'
default['myapp']['port']         = 8080
default['myapp']['java_package'] = 'openjdk-21-jre-headless'
default['myapp']['jvm_opts']     = '-Xms128m -Xmx256m'
default['myapp']['log_level']    = 'INFO'
default['myapp']['greeting']     = 'Hello from Chef'

# Where Jenkins publishes the built jar (nginx on the Jenkins VM).
default['myapp']['artifact_base_url'] = 'http://jenkins.lab.internal:8081/myapp'

# Data bag that tells each policy group WHICH app version to run.
# Jenkins writes items named "myapp_<policy_group>", e.g. releases/myapp_dev.
default['myapp']['release_data_bag'] = 'releases'

# Encrypted data bag holding the app's secrets (never in Git, never in attributes).
default['myapp']['secrets_data_bag'] = 'secrets'

# Open the app port in the base cookbook's firewall (hash merge, no array juggling).
default['base']['firewall']['allow']['myapp'] = 8080
