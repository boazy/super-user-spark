# Super User Spark
[![Build Status](https://travis-ci.org/NorfairKing/super-user-spark.svg?branch=master)](https://travis-ci.org/NorfairKing/super-user-spark)

A safe way to never worry about your beautifully configured system again.

## Example

If your dotfiles repository looks like this...

```
dotfiles
├── bashrc
├── bash_aliases
├── bash_profile
└── README
```

... then you can now deploy those dotfiles with this `.sus` file using `spark`!

``` super-user-spark
card bash {
  into ~

  .bashrc
  .bash_aliases
  .bash_profile
}
```

Find out more in the documentation below.

## Documentation
Most of the documentation is in the `doc` directory.

- [Installation](https://github.com/NorfairKing/super-user-spark/blob/master/doc/installation.md)
- [Getting Started](https://github.com/NorfairKing/super-user-spark/blob/master/doc/getting-started.md)
- [Usage](https://github.com/NorfairKing/super-user-spark/blob/master/doc/usage.md)
- [Design](https://github.com/NorfairKing/super-user-spark/blob/master/doc/pillars.md)
- [Language Specifications](https://github.com/NorfairKing/super-user-spark/blob/master/doc/language.md)
- [FAQ](https://github.com/NorfairKing/super-user-spark/blob/master/doc/faq.md)

## SUS Depot Examples
If you would like to have your name on this list, just send a pull request.

- [NorfairKing](https://github.com/NorfairKing/sus-depot)
- [plietar](https://github.com/plietar/dotfiles)
- [mkirsche](https://github.com/mkirsche/sus-depot)
- [badi](https://github.com/badi/dotfiles/blob/master/deploy.sus)
- [tilal6991](https://github.com/tilal6991/.dotfiles)

## Contributing
Before contributing, make sure you installed the pre-commit tests:

```
spark deploy hooks.sus
```

## Found a problem?

Raise an issue or, even better, do a pull-request with a failing test!
