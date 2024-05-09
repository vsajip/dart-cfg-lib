# cfg_lib

A Dart library for working with the CFG configuration format.

## Installation

The package can be installed by adding `cfg_lib` to your list of dependencies in `pubspec.yaml`:

```yaml
cfg_lib: ^0.1.1
```

There’s a minimal example of a program that uses CFG [here](https://github.com/vsajip/cfgclient/tree/main/dart).

## Usage

The CFG configuration format is a text format for configuration files which is similar to, and a superset of, the JSON format. It dates from before its first announcement in [2008](https://wiki.python.org/moin/HierConfig) and has the following aims:

* Allow a hierarchical configuration scheme with support for key-value mappings and lists.
* Support cross-references between one part of the configuration and another.
* Provide a string interpolation facility to easily build up configuration values from other configuration values.
* Provide the ability to compose configurations (using include and merge facilities).
* Provide the ability to access real application objects safely, where supported by the platform.
* Be completely declarative.

It overcomes a number of drawbacks of JSON when used as a configuration format:

* JSON is more verbose than necessary.
* JSON doesn’t allow comments.
* JSON doesn’t provide first-class support for dates and multi-line strings.
* JSON doesn’t allow trailing commas in lists and mappings.
* JSON doesn’t provide easy cross-referencing, interpolation, or composition.

A simple example
================

With the following configuration file, `test0.cfg`:
```text
a: 'Hello, '
b: 'world!'
c: {
  d: 'e'
}
'f.g': 'h'
christmas_morning: `2019-12-25 08:39:49`
home: `$HOME`
foo: `$FOO|bar`
```

You can load and query the above configuration using [Repl.it](https://replit.com/join/lrrwrhazkb-vsajip):

Loading a configuration
-----------------------

The configuration above can be loaded as shown below:
```dart
var cfg = Config.fromFile('test0.cfg');
```

The successful call returns a `Config` which can be used to query the configuration.

Access elements with keys
-------------------------
Accessing elements of the configuration with a simple key is not much harder than using a map:
```dart
print('a is "${cfg['a']}"');
print('b is "${cfg['b']}"');
```

which prints:

```shell
a is "Hello, "
b is "world!"
```

Access elements with paths
--------------------------
As well as simple keys, elements can also be accessed using path strings:
```dart
print('c.d is "${cfg['c.d']}"');
```

which prints:

```shell
c.d is "e"
```
Here, the desired value is obtained in a single step, by (under the hood) walking the path `c.d` – first getting the mapping at key `c`, and then the value at `d` in the resulting mapping.

Note that you can have simple keys which look like paths:
```dart
print('f.g is "${cfg['f.g']}"');
```
which prints:

```shell
f.g is "h"
```

If a key is given that exists in the configuration, it is used as such, and if it is not present in the configuration, an attempt is made to interpret it as a path. Thus, `f.g` is present and accessed via key, whereas `c.d` is not an existing key, so is interpreted as a path.

Access to date/time objects
---------------------------
You can also get native Elixir date/time objects from a configuration, by using an ISO date/time pattern in a backtick-string:
```dart
print('Christmas morning is ${cfg['christmas_morning']} (${cfg['christmas_morning'].runtimeType})');
```

which prints:
```shell
Christmas morning is 2019-12-25 08:39:49.000Z (DateTime)
```
As Dart doesn’t currently support timezone-aware date/times out of the box, currently the approach used is to compute the offset and add to the UTC time to yield the result. Although there are some third-party timezone-aware libraries around, they don’t allow computing an offset and setting it on the date/time - they work from timezone names.

Access to environment variables
-------------------------------
To access an environment variable, use a backtick-string of the form `$VARNAME`:
```dart
print(cfg['home'] == Platform.environment['HOME']);
```

which prints:
```shell
true
```

You can specify a default value to be used if an environment variable isn’t present using the `$VARNAME|default-value` form. Whatever string follows the pipe character (including the empty string) is returned if the VARNAME is not a variable in the environment.
```dart
print('foo is "${cfg['foo']}"');
```

which prints:
```shell
foo is "bar"
```
For more information, see [the CFG documentation](https://docs.red-dove.com/cfg/index.html).
