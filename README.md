# send

Crystal looks and feels a lot like Ruby. However, pieces of the metaprogramming toolkits between the two languages vary quite widely. The high level difference is that Ruby makes extensive use of facilities like `eval`, `method_missing`, and `send` to do its dynamic magic. And while Crystal does support `method_missing`, because of its compiled nature, most of Crystal's dynamic magic comes from the use of macros. Crystal does not support `eval` or  `send`.

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

  def e(&blk)
    blk.call
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

That's what this shard does for you. It leverages Crystal's powerful macro system to build code that is similar to the above examples. This, in turn, let's one utilize `#send` to do dynamic method dispatch.

And while it might seem like this would slow down that method dispatch, the benchmarks prove otherwise. 

```
direct 386.16M (  2.59ns) (± 1.79%)  0.0B/op   1.00× slower
  send 386.25M (  2.59ns) (± 0.74%)  0.0B/op        fastest
```

For all intents and purposes, when running code build with `--release`, the execution speed between the direct calls and the `#send` based calls is the same.

## Limitations

This approach currently has some significant limitations. First, it will not work automatically on any method which does not have a type definition. Crystal must expand macros into code before type inference runs, so arguments with no provided 

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     send:
       github: your-github-user/send
   ```

2. Run `shards install`

## Usage

```crystal
require "send"
```

TODO: Write usage instructions here

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/your-github-user/send/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Kirk Haines](https://github.com/your-github-user) - creator and maintainer
