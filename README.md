# CMDB

[![TravisCI](https://travis-ci.org/rightscale/cmdb.svg?branch=master)](https://travis-ci.org/rightscale/cmdb) [![Coverage](https://coveralls.io/repos/github/rightscale/cmdb/badge.svg?branch=master)](https://coveralls.io/github/rightscale/cmdb?branch=master)

CMDB is a Ruby interface for consuming data from one or more configuration management databases
(CMDBs) and making that information available to Web applications.

It is intended to support multiple CM technologies, including:
  - consul
  - JSON/YAML files on a local disk
  - (someday) etcd
  - (someday) ZooKeeper

Maintained by
 - [RightScale Inc.](https://www.rightscale.com)

## Why should I use this gem?

With CMDB, you can:

  1. Decouple your modern (12-factor) application from the CM tools used to deploy it
  2. Deploy legacy applications by rewriting config files at app-load time
  3. Interact with your CMDB using a beautiful shell

CMDB has three primary interfaces:

  1. The `cmdb shell` command navigates your k/v store using filesystem-like
     metaphors (`ls`, `cd`, and so forth) with color output and tab completion
  2. The `cmdb shim` command populates the environment with values and/or rewrites hardcoded
     config files, then spawns your application.
  3. The `CMDB::Interface` object provides a programmatic API for querying CMDBs. Its `#to_env`
     method transforms the whole configuration into an environment-friendly hash if you prefer to seed the
     environment yourself, without using the shim.

# Getting Started

## Determine sources

Sources are specified with the `--source` option when you run the CLI. This
option applies to all subcommands (`shim`, `shell`, etc) and must appear
before the subcommand name.

You can add as many sources as you'd like. All sources are specified as a URI,
where the scheme tells CMDB which driver to use and how to interpret the rest
of the URI.

Examples:

  * `file:///var/lib/cmdb/myapp.yml` creates a file source with the prefix
    `myapp`; the value `foo: bar` in the file would have the key `myapp.foo`
  * `consul://localhost` creates a source with no key prefix that talks to a local
    consul agent on the standard port (8500); a value `foo/bar` in Consul would
    have the key `foo.bar
  * `consul://kv:18500/myapp` creates a source with the prefix `myapp.` that
    talks to a remote consul agent on a nonstandard port (18500); this source
    only "sees" Consul values under the path `/myapp/` and their key
    names always begin with `myapp.`
  * `consul://localhost/mycorp/staging/myapp` creates a source with the prefix
    `myapp.`; this source only "sees" Consul values under the path
    `staging/myapp` and their key names always begin with `myapp.`
  * `consul://localhost/mycorp/staging` creates a source with the prefix `staging.`
    that has all keys in the staging environment. (It is probably a bad idea to
    use this source with the `myapp` source in the example above!)

If no sources are specified on the command line, CMDB will run an auto-detect
algorithm to check for network agents listening at localhost.

To learn more about sources and prefixes, see "Data model," below.

## Invoke the CMDB Shell

To enter an interactive sh-like shell, just type `cmdb shell`.

## Invoke the CMDB Shim

For non-Ruby applications, or for situations where CMDB values are required
outside of the context of interpreted code, use `cmdb shim` to run
your application. The shim can do several things for you:

1. Make CMDB values available to your app (in `ENV`, or by rewriting files)
2. Change the user before invoking your app (e.g. drop privileges to `www-data`)
3. Watch for filesystem changes and reload your app on demand

### Populate the environment for a dotenv-compatible application

If you have an app that uses 12-factor (dotenv) style configuration, the shim
can populate the environment with CMDB values:

    bundle exec cmdb shim

    # Now your app can refer to ENV['DB_HOSTNAME'] or ENV['WIDGETS_FLAVORS]
    # Note missing "my_app" prefix that would be present if you asked for these using their CMDB key names

Note that when we export CMDB keys into the environment, we _remove_ the prefix of
each key; in the example above, the values could have come from `common.db.hostname`
and `myapp.widgets.flavors` but their names have been simplified. If any two sources
have keys whose simplified names are identical, CMDB prints a detailed error message
and fails rather than putting ambiguous data into the environment.

Note that the data type of CMDB inputs is preserved: lists remain lists, numbers remain numbers,
and so forth. This works irrespective of the format of your configuration files, and also holds true
for CMDB values that are serialized to the environment (as a JSON document, in the case of lists).

### Rewrite static configuration files with dynamic CMDB values

If the `--rewrite` option is provided, the shim recursively scans the provided
subdirectory for data files that contain replacement tokens; when a token is
found, it substitutes the corresponding CMDB key's value.

Replacement tokens look like this: `<<name.of.my.key>>` and can appear anywhere in a file as a YAML
or JSON _value_ (but never a key). Unlike environment variables, replacement tokens always use
the fully-qualified key name, including prefix.

Replacement tokens should appear inside string literals in your configuration files so they don't
invalidate syntax or render the files unparsable by other tools.

The shim performs replacement in-memory and saves all of the edits at once, making the rewrite
operation nearly atomic. If any keys are missing, then no files are changed on disk and the shim
exits with a helpful error message.

Given `my_app.yml` and an application with two configuration files:

    # config/database.yml
    production:
      host: <<my_app.db.hostname>
      database: my_app_production

    # config/widgets.json
    {'widgetFlavors': '<<my_app.widgets.flavors>>'}

I can run the following command in my application's root directory:

    bundle exec cmdb shim --dir=config rackup

This will rewrite the files under config, replacing my configuration files as
follows:

    # config/database.yml
    production:
      host: db1.local
      database: my_app_production

    # config/widgets.json
    {'widgetFlavors':['vanilla', 'chocolate']}

### Drop Privileges

If your app doesn't know how to safely switch to a non-privileged user, the shim
can do this for you. Just add the `--user` flag when you invoke it:

    bundle exec cmdb shim --user=www-data whoami

# Data Sources

## Network Servers

To read CMDB data from a consul server, add a CLI parameter such as
`--source=consul://some-host/key/subkey`. This will create a source whose
prefix is `subkey` that encompasses the  subtree of the k/v store that lies
underneath `/key/subkey`.

## Flat Files

To read CMDB data from a flat file on disk, add a CLI parameter such as
`--source=file:///var/lib/cmdb/mykeys.yml`. This will parse the YAML file
located in `/var/lib/cmdb` and present it as a source whose prefix is `mykeys`.

JSON and YAML files are both supported. The structured data within each file
can contain arbitrarily-deep subtrees which are interpreted as subkeys,
sub-subkeys and so forth.

# Data Model

CMDB models all data sources as trees whose nodes are named, and whose leaf
nodes can contain a piece of data: strings, numbers, booleans, or arrays.

Maps are disallowed on order to prevent ambiguity; a map always represents a
subtree of the k/v store, never a value. Mixed-type arrays are disallowed
because they can cause problems with strongly-typed languages. Nil is
disallowed as a value because writing nil means "delete the key."

Paths within a tree -- and therefore CMDB keys -- are identified using a dot
notation similar to Java properties; for instance, `production.http.listen_port`
might be an Integer-valued key that tells your microservice which HTTP port
to listen on in the production environment; `production.database.host` might be
the database host, and so forth. The names of keys are determined by the tree
structure of your k/v store, and when you set a key through CMDB, its position
in the tree is derived from its key name.

## Source Prefixes

CMDB sources have a `prefix`, meaning that _all_ keys contained in
that source begin with the same prefix. No two sources may share a prefix,
ensuring that sources don't "hide" each others' data. The prefix of a source is
usually automatically determined by the final component of its URL, e.g. the
filename in the case of `file://` sources and the final path component in the
case of `consul://` or other network sources.

## Inheritance

The uniqueness constraint on prefixes means that all sources' keys are
disjoint; there is no such thing as "inheritance" in the CMDB data model.

When keys are exported to the environment, the prefix is stripped from the
key name; however, CMDB _still_ prevents overlap in this case.

Inheritance may be supported in future as an optional behavior, but is omitted
for the time being because in practice, it causes more problems than it solves.

## Ambiguous Key Names

Consider a file that defines the following variables:

    # confusing.yml
    this:
      is:
        ambiguous
      was:
        very: ambiguous
        extremely: confusing

At first glance, ths file defines two CMDB keys:
  - `confusing.this.is` (a string)
  - `confusing.this.was` (a map)

However, an equally valid interpretation would be:
  - `confusing.this.is`
  - `confusing.this.was.very`
  - `confusing.this.was.extremely`

Because CMDB keys cannot contain maps, the first interpretation is wrong. The second
interpretation is valid according to the data model, but results in a situation where the type
of the keys could change if the structure of the YML file changes.

For this reason, any YAML file that defines an "ambiguous" key name will cause an error at
initialization time. To avoid ambiguous key names, think of your YAML file as a tree and remember
that _leaf nodes must define data_ and _internal nodes must define structure_.
