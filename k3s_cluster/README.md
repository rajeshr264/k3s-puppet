# k3s_cluster

Welcome to your new module. A short overview of the generated parts can be found
in the [PDK documentation][1].

The README template below provides a starting point with details about what
information to include in your README.

## Table of Contents

1. [Description](#description)
1. [Setup - The basics of getting started with k3s_cluster](#setup)
    * [What k3s_cluster affects](#what-k3s_cluster-affects)
    * [Setup requirements](#setup-requirements)
    * [Beginning with k3s_cluster](#beginning-with-k3s_cluster)
1. [Usage - Configuration options and additional functionality](#usage)
1. [Limitations - OS compatibility, etc.](#limitations)
1. [Development - Guide for contributing to the module](#development)
1. [Features](#features)
1. [RPM Lock Handling](#rpm-lock-handling)

## Description

Briefly tell users why they might want to use your module. Explain what your
module does and what kind of problems users can solve with it.

This should be a fairly short description helps the user decide if your module
is what they want.

## Setup

### What k3s_cluster affects **OPTIONAL**

If it's obvious what your module touches, you can skip this section. For
example, folks can probably figure out that your mysql_instance module affects
their MySQL instances.

If there's more that they should know about, though, this is the place to
mention:

* Files, packages, services, or operations that the module will alter, impact,
  or execute.
* Dependencies that your module automatically installs.
* Warnings or other important notices.

### Setup Requirements **OPTIONAL**

If your module requires anything extra before setting up (pluginsync enabled,
another module, etc.), mention it here.

If your most recent release breaks compatibility or requires particular steps
for upgrading, you might want to include an additional "Upgrading" section here.

### Beginning with k3s_cluster

The very basic steps needed for a user to get the module up and running. This
can include setup steps, if necessary, or it can be an example of the most basic
use of the module.

## Usage

Include usage examples for common use cases in the **Usage** section. Show your
users how to use your module to solve problems, and be sure to include code
examples. Include three to five examples of the most important or common tasks a
user can accomplish with your module. Show users how to accomplish more complex
tasks that involve different types, classes, and functions working in tandem.

## Reference

This section is deprecated. Instead, add reference information to your code as
Puppet Strings comments, and then use Strings to generate a REFERENCE.md in your
module. For details on how to add code comments and generate documentation with
Strings, see the [Puppet Strings documentation][2] and [style guide][3].

If you aren't ready to use Strings yet, manually create a REFERENCE.md in the
root of your module directory and list out each of your module's classes,
defined types, facts, functions, Puppet tasks, task plans, and resource types
and providers, along with the parameters for each.

For each element (class, defined type, function, and so on), list:

* The data type, if applicable.
* A description of what the element does.
* Valid values, if the data type doesn't make it obvious.
* Default value, if any.

For example:

```
### `pet::cat`

#### Parameters

##### `meow`

Enables vocalization in your cat. Valid options: 'string'.

Default: 'medium-loud'.
```

## Limitations

In the Limitations section, list any incompatibilities, known issues, or other
warnings.

## Development

In the Development section, tell other users the ground rules for contributing
to your project and how they should submit their work.

## Release Notes/Contributors/Etc. **Optional**

If you aren't using changelog, put your release notes here (though you should
consider using changelog). You can also add any additional sections you feel are
necessary or important to include here. Please use the `##` header.

## Features

- **Flexible Installation**: Support for both script-based and binary installation methods
- **Multi-Node Support**: Configure server and agent nodes with automated token sharing
- **High Availability**: Support for external datastores and embedded etcd
- **Configuration Management**: YAML-based configuration with merge capabilities
- **Service Management**: Systemd service configuration with health checks
- **Complete Uninstallation**: Clean removal including containers, network, and iptables
- **Platform Support**: Multiple OS families (RedHat, Debian, SUSE) and architectures
- **Automated Token Sharing**: Exported resources for seamless multi-node deployment
- **RPM Lock Handling**: Built-in handling of package manager conflicts on RPM-based systems
- **Retry Logic**: Automatic retry mechanisms for robust installation on cloud environments

## RPM Lock Handling

This module includes built-in handling for RPM transaction lock issues commonly encountered on RHEL-based systems, especially in cloud environments like AWS EC2. The module automatically:

- **Detects RPM locks** before installation attempts
- **Waits for lock release** with configurable timeout (5 minutes)
- **Cleans up hanging processes** (yum, dnf, rpm, packagekit)
- **Temporarily stops conflicting services** (AWS SSM agent, packagekit)
- **Implements retry logic** with 3 attempts and 30-second delays
- **Restarts services** after successful installation

### Supported Scenarios

The RPM lock handling addresses these common issues:
- AWS Systems Manager agent running automatic updates
- Cloud-init installing packages simultaneously
- Multiple package manager processes running concurrently
- Stale lock files from interrupted operations

### Manual Troubleshooting

If you encounter persistent RPM lock issues, you can run the lock handler manually:

```bash
# The module creates this script automatically
sudo /tmp/rpm-lock-handler.sh
```

Or check for locks manually:
```bash
# Check if RPM database is locked
sudo fuser /var/lib/rpm/.rpm.lock

# Wait for lock release
while sudo fuser /var/lib/rpm/.rpm.lock >/dev/null 2>&1; do
  echo "Waiting for RPM lock..."
  sleep 10
done
```

[1]: https://puppet.com/docs/pdk/latest/pdk_generating_modules.html
[2]: https://puppet.com/docs/puppet/latest/puppet_strings.html
[3]: https://puppet.com/docs/puppet/latest/puppet_strings_style.html
