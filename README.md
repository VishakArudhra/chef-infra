# chef-infra

Infrastructure code for the on-prem lab: Chef (Cinc) cookbooks, the policy that
ties them together, the CI/CD scripts, and the VM definitions.

```
chef-infra/
├── lab/                      VMs on the Windows laptop (Vagrant + VirtualBox)
│   ├── lab.yml               ← edit: Wi-Fi adapter name, subnet, IPs
│   ├── Vagrantfile
│   ├── keys/                 ← drop your Mac's public key here before `vagrant up`
│   └── scripts/              common / chef-server / jenkins provisioning
├── cookbooks/
│   ├── base/                 hardening, deploy user, firewall, scheduled cinc-client
│   └── myapp/                Java, service user, jar download, config, systemd
│       ├── kitchen.yml       Test Kitchen (dokken) → runs the real policy in Docker
│       ├── spec/             ChefSpec unit tests
│       └── test/integration/ InSpec tests for Kitchen
├── policyfiles/myapp.rb      run list + pinned cookbook versions (+ myapp.lock.json)
├── approved-versions.json    release manifest checked before every promotion
├── test/smoke/               InSpec profile run against real nodes after deploy
├── ci/                       scripts used by both Jenkins pipelines
│   ├── check_versions.py     dependency gate
│   ├── deploy_policy.sh      gate → cinc push → converge → verify
│   ├── release_app.sh        set app version for a group → converge → verify
│   ├── converge.sh           knife ssh … sudo cinc-client
│   └── smoke.sh              cinc-auditor exec test/smoke over SSH
├── .chef/config.rb           knife config (keys beside it are git-ignored)
└── Jenkinsfile               cookbook pipeline: lint → unit → kitchen → dev → uat → prod
```

## Everyday commands (from the repo root on your Mac)

```bash
cookstyle -a cookbooks/                       # lint + auto-fix
(cd cookbooks/myapp && cinc exec rspec)       # unit tests
cinc update policyfiles/myapp.rb              # after changing a cookbook version
cinc push dev policyfiles/myapp.rb            # push the lock to a policy group
knife status                                  # when did each node last run?
knife node show app01 -a myapp                # what attributes did app01 get?
DEPLOY_KEY=~/chef-lab-keys/jenkins_deploy ci/converge.sh dev
```

See the walkthrough for the full setup, in order.
