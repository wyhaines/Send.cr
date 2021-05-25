# send

![CSUUID CI](https://img.shields.io/github/workflow/status/wyhaines/Send.cr/Send.cr%20CI?style=for-the-badge&logo=GitHub)
[![GitHub release](https://img.shields.io/github/release/wyhaines/Send.cr.svg?style=for-the-badge)](https://github.com/wyhaines/Send.cr/releases)
![GitHub commits since latest release (by SemVer)](https://img.shields.io/github/commits-since/wyhaines/Send.cr/latest?style=for-the-badge)

Crystal looks and feels a lot like Ruby. However, pieces of the metaprogramming toolkits between the two languages are very different. The high level difference is that Ruby makes extensive use of facilities like `eval`, `method_missing`, and `send` to do its dynamic magic. And while Crystal does support `method_missing`, because of its compiled nature, most of Crystal's dynamic magic comes from the use of macros. Crystal does not support `eval` or  `send`.

However...

Consider this program:

```crystal
require "secret_sauce"

class Foo
  def a(val : Int32)
    val + 7
  end

  def b(x : Int32, y : Int32)
    x * y
  end

  def c(val : Int32, val2 : Int32)
    val * val2
  end

  def d(xx : String, yy : Int32) : UInt128
    xx.to_i.to_u128 ** yy
  end

  include SecretSauce
end

f = Foo.new
puts f.b(7, 9)
puts "------"
puts f.send("a", 7)
puts f.send("b", 7, 9)
puts f.send("d", "2", 64)
```

Will it work? Of course! Why else would you be reading this?

```
63                          
------
14
63
18446744073709551616
```

In this example, SecretSauce is a proof of concept implementation:

```crystal
module SecretSauce
  SendLookupInt32 = {
    "a": ->(obj : Foo, val : Int32) { obj.a(val) },
  }

  SendLookupInt32Int32 = {
    "b": ->(obj : Foo, x : Int32, y : Int32) { obj.b(x, y) },
    "c": ->(obj : Foo, val : Int32, val2 : Int32) { obj.c(val, val2) },
  }

  def send(method, arg1 : Int32)
    SendLookupInt32[method].call(self, arg1)
  end

  def send(method, arg1 : Int32, arg2 : Int32)
    SendLookupInt32Int32[method].call(self, arg1, arg2)
  end
end
```

It works by creating a set of lookup tables that match method names to their argument type signature set.

When paired with overloaded `#send` methods, one per argument type signature set, it is a fairly simple matter to lookup the method name, and to call the proc with the matching arguments.

That is essentially what this shard does for you. It leverages Crystal's powerful macro system to build code that is similar to the above examples. This, in turn, let's one utilize `#send` to do dynamic method dispatch.

And while it might seem like this would slow down that method dispatch, the benchmarks prove otherwise. 

```
Benchmarks...
 direct method invocation -- nulltest 769.43M (  1.30ns) (Â± 1.76%)  0.0B/op        fastest
send via record callsites -- nulltest 767.27M (  1.30ns) (Â± 4.33%)  0.0B/op   1.00x slower
  send via proc callsites -- nulltest 511.92M (  1.95ns) (Â± 2.33%)  0.0B/op   1.50x slower
 direct method invocation 384.59M (  2.60ns) (Â± 1.91%)  0.0B/op        fastest
send via record callsites 383.23M (  2.61ns) (Â± 3.04%)  0.0B/op   1.00x slower
  send via proc callsites 230.41M (  4.34ns) (Â± 2.39%)  0.0B/op   1.67x slower

```

For all intents and purposes, when running code build with `--release`, the execution speed between the direct calls and the `#send` based calls is the same, when using *record* type callsites. It is somewhat slower when using *proc* type callsites, but the performance is still reasonably good.

## Limitations

This approach currently has some significant limitations.

### Methods can't be sent to if they do not have type definitions

First, it will not work automatically on any method which does not have a type definition. Crystal must expand macros into code before type inference runs, so arguments with no provided method types lack the information needed to build the callsites.

This is because both of the techniques used to provide callsites, the use of *Proc* or the use of a *record*, require this type information. Proc arguments must have types, and will return a `Error: function argument ZZZ must have a type` if one is not provided. The *record* macro, on the other hand, builds instance variables for the arguments, which, again, require types to be provided at the time of declaration.

A possible partial remediation that would allow one to retrofit the ability to use `send` with methods that aren't already defined with fully typing would be to enable the use of annotations to describe the type signature for the method. This would allow someone to reopen a class, attach type signatures to the methods that need them, and then include `Send` in the class to enable sending to those methods.

### Methods that take blocks are currently unsupported

This can be supported. The code to do it is still just TODO.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     send:
       github: your-github-user/send
   ```

2. Run `shards install`

## Usage

```
require "send"

class Foo
  def abc(n : Int32)
    n * 123
  end

  include Send
end
```

When `Send` is included into a class, it will setup callsites for all methods that have been defined before that point, which have type definitions on their arguments. By default, this uses *record* callsites for everything. When compiled with `--release`, using *record* callsites is as fast as directly calling the method. If a method uses types that can not be used with an instance variable, but are otherwise legal method types, the *Proc* callsite type can be used instead.

To specify that the entire class should use one callsite type or another, use an annotation on the class.

```
@[SendViaProc]
class Foo
end
```

The `@[SendViaRecord]` annotation is also supported, but since that is the default, one should not need to use it at the class level.

These same annotations can also be used on methods to specify the `send` behavior for a given method.

```
@[SendViaProc]
class Foo
  def abc(n : Int32)
    n ** n
  end

  @[SendViaRecord]
  def onetwothree(x : Int::Signed | Int::Unsigned, y : Int::Signed | Int::Unsigned)
    BigInt.new(x) ** BigInt.new(y)
  end
end
```

The 

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/wyhaines/send/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Kirk Haines](https://github.com/wyhaines) - creator and maintainer

![GitHub code size in bytes](https://img.shields.io/github/languages/code-size/wyhaines/Send.cr?style=for-the-badge)
![GitHub issues](https://img.shields.io/github/issues/wyhaines/Send.cr?style=for-the-badge)
