#!/usr/bin/env python3
"""Dependency gate: run before every `cinc push` to a policy group.

This is the check from Vishak's UAT story: catch a wrong or leftover version pin
*before* it reaches a server, not after chef-client fails there.

It fails the build (exit 1) when:
  1. a cookbook in the policy lock is not allowed by approved-versions.json, or
  2. the lock is stale: a cookbook's metadata.rb version differs from the lock
     (someone bumped a version but forgot `cinc update`).
It also prints what the target policy group runs *right now* versus what is about
to be pushed, and flags drift on that group (e.g. a manual push from a laptop).

Usage:
  python3 ci/check_versions.py --lock policyfiles/myapp.lock.json \
      --approved approved-versions.json [--group uat --knife-config .chef/config.rb]
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


def parse_version(v):
    return tuple(int(x) for x in v.strip().split("."))


def satisfies(version, constraint):
    """Support the constraint styles Chef uses: '1.2.3', '= 1.2.3', '>= 1.2', '~> 1.2'."""
    constraint = constraint.strip()
    m = re.match(r"^(=|>=|<=|>|<|~>)?\s*([\d.]+)$", constraint)
    if not m:
        raise ValueError(f"unsupported constraint: {constraint!r}")
    op, target = m.group(1) or "=", m.group(2)
    v = parse_version(version)
    t_parts = parse_version(target)
    t = t_parts + (0,) * (3 - len(t_parts))
    v = v + (0,) * (3 - len(v))
    if op == "=":
        return v == t
    if op == ">=":
        return v >= t
    if op == "<=":
        return v <= t
    if op == ">":
        return v > t
    if op == "<":
        return v < t
    # Pessimistic: '~> 1.2' -> >=1.2,<2.0 ; '~> 1.2.3' -> >=1.2.3,<1.3
    upper = list(t_parts[:-1])
    if len(upper) == 0:
        return v >= t
    upper[-1] += 1
    upper = tuple(upper) + (0,) * (3 - len(upper))
    return t <= v < upper


def metadata_version(cookbook_dir):
    meta = Path(cookbook_dir) / "metadata.rb"
    if not meta.exists():
        return None
    m = re.search(r"^\s*version\s+['\"]([^'\"]+)['\"]", meta.read_text(), re.M)
    return m.group(1) if m else None


def current_group_lock(group, policy, knife_config):
    cmd = ["knife", "raw", f"/policy_groups/{group}/policies/{policy}"]
    if knife_config:
        cmd += ["-c", knife_config]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
        return json.loads(out)
    except FileNotFoundError:
        print("  (knife not found - skipping current-state comparison)")
    except subprocess.CalledProcessError:
        print(f"  (policy '{policy}' not yet pushed to group '{group}')")
    except json.JSONDecodeError:
        print("  (could not parse knife raw output)")
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lock", required=True)
    ap.add_argument("--approved", required=True)
    ap.add_argument("--group")
    ap.add_argument("--knife-config")
    ap.add_argument("--fail-on-drift", action="store_true",
                    help="also fail if the group currently runs unapproved versions "
                         "(used before an APP release: don't deploy onto a drifted environment)")
    args = ap.parse_args()

    lock_path = Path(args.lock)
    lock = json.loads(lock_path.read_text())
    approved = json.loads(Path(args.approved).read_text())
    allowed = approved["cookbooks"]
    policy = lock.get("name", approved.get("policy"))
    locks = lock["cookbook_locks"]

    errors = []
    print(f"== Dependency gate for policy '{policy}' ==")
    print(f"{'cookbook':<16}{'in lock':<12}{'approved':<14}{'metadata.rb':<14}result")
    for name, info in sorted(locks.items()):
        version = info["version"]
        rule = allowed.get(name)
        src_path = info.get("source_options", {}).get("path")
        meta_v = metadata_version((lock_path.parent / src_path).resolve()) if src_path else None
        problems = []
        if rule is None:
            problems.append("not in approved-versions.json")
        elif not satisfies(version, rule):
            problems.append(f"{version} not allowed by '{rule}'")
        if meta_v and meta_v != version:
            problems.append(f"stale lock (metadata.rb says {meta_v}; run `cinc update`)")
        print(f"{name:<16}{version:<12}{rule or '-':<14}{meta_v or '-':<14}{'OK' if not problems else 'FAIL'}")
        errors += [f"{name}: {p}" for p in problems]

    if args.group:
        print(f"\n== Policy group '{args.group}': now -> after push ==")
        current = current_group_lock(args.group, policy, args.knife_config)
        if current:
            cur_locks = current.get("cookbook_locks", {})
            for name in sorted(set(cur_locks) | set(locks)):
                now = cur_locks.get(name, {}).get("version", "-")
                new = locks.get(name, {}).get("version", "-")
                drift = ""
                if name in cur_locks and name in allowed and not satisfies(now, allowed[name]):
                    drift = "  <- DRIFT: running an unapproved version"
                    if args.fail_on_drift:
                        errors.append(f"{name}: group '{args.group}' runs {now}, approved is "
                                      f"'{allowed[name]}' - re-run the chef-infra pipeline to fix")
                print(f"  {name:<14}{now:>10} -> {new:<10}{'(changed)' if now != new else ''}{drift}")

    if errors:
        print("\nGATE FAILED:")
        for e in errors:
            print(f"  - {e}")
        print("Fix the cookbook version / policy lock, get the new version approved in "
              "approved-versions.json (reviewed commit), or re-promote the approved policy.")
        return 1
    print("\nGATE PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
