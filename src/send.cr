ClassesToEnable = [] of String

# Classes or methods with this annotation will use a Proc to wrap method calls.
annotation SendViaProc
end

# Classes or methods with this annotation will use a record to wrap method calls.
annotation SendViaRecord
end

# Methods with this annotation will be skipped when building send call sites.
annotation SendSkip
end

# Crystal looks and feels a lot like Ruby. However, pieces of the metaprogramming toolkits between the two languages are very different. The high level difference is that Ruby makes extensive use of facilities like `eval`, `method_missing`, and `send` to do its dynamic magic. And while Crystal does support `method_missing`, because of its compiled nature, most of Crystal's dynamic magic comes from the use of macros. Crystal does not support `eval` or  `send`.
#
# However...
#
# Consider this program:
#
# ```crystal
# require "secret_sauce"
#
# class Foo
#   include Send
#
#   def a(val : Int32)
#     val + 7
#   end
#
#   def b(x : Int32, y : Int32)
#     x * y
#   end
#
#   def c(val : Int32, val2 : Int32)
#     val * val2
#   end
#
#   def d(xx : String, yy : Int32) : UInt128
#     xx.to_i.to_u128 ** yy
#   end
# end
#
# Send.activate
#
# f = Foo.new
# puts f.b(7, 9)
# puts "------"
# puts f.send("a", 7)
# puts f.send("b", 7, 9)
# puts f.send("d", "2", 64)
# ```
#
# Will it work? Of course! Why else would you be reading this?
#
# ```
# 63
# ------
# 14
# 63
# 18446744073709551616
# ```
#
# In this example, SecretSauce is a proof of concept implementation:
#
# ```crystal
# module SecretSauce
#   SendLookupInt32 = {
#     "a": ->(obj : Foo, val : Int32) { obj.a(val) },
#   }
#
#   SendLookupInt32Int32 = {
#     "b": ->(obj : Foo, x : Int32, y : Int32) { obj.b(x, y) },
#     "c": ->(obj : Foo, val : Int32, val2 : Int32) { obj.c(val, val2) },
#   }
#
#   def send(method, arg1 : Int32)
#     SendLookupInt32[method].call(self, arg1)
#   end
#
#   def send(method, arg1 : Int32, arg2 : Int32)
#     SendLookupInt32Int32[method].call(self, arg1, arg2)
#   end
# end
# ```
#
# It works by creating a set of lookup tables that match method names to their argument type signature set.
#
# When paired with overloaded `#send` methods, one per argument type signature set, it is a fairly simple matter to lookup the method name, and to call the proc with the matching arguments.
#
# That is essentially what this shard does for you. It leverages Crystal's powerful macro system to build code that is similar to the above examples. This, in turn, let's one utilize `#send` to do dynamic method dispatch.
#
# And while it might seem like this would slow down that method dispatch, the benchmarks prove otherwise.
#
# ```
# Benchmarks...
#   direct method invocation -- nulltest 771.44M (  1.30ns) (± 1.67%)  0.0B/op        fastest
# send via record callsites -- nulltest 768.43M (  1.30ns) (± 2.71%)  0.0B/op   1.00x slower
#   send via proc callsites -- nulltest 367.63M (  2.72ns) (± 1.25%)  0.0B/op   2.52x slower
#   direct method invocation 386.46M (  2.59ns) (± 1.17%)  0.0B/op        fastest
# send via record callsites 384.89M (  2.60ns) (± 3.20%)  0.0B/op   1.00x slower
#   send via proc callsites 220.40M (  4.54ns) (± 1.57%)  0.0B/op   1.75x slowerr
#
# ```
#
# For all intents and purposes, when running code build with `--release`, the execution speed between the direct calls and the `#send` based calls is the same, when using *record* type callsites. It is somewhat slower when using *proc* type callsites, but the performance is still reasonably good.
#
# ## Limitations
#
# This approach currently has some significant limitations.
#
# ### Methods can't be sent to if they do not have type definitions
#
# First, it will not work automatically on any method which does not have a type definition. Crystal must expand macros into code before type inference runs, so arguments with no provided method types lack the information needed to build the callsites.
#
# This is because both of the techniques used to provide callsites, the use of *Proc* or the use of a *record*, require this type information. Proc arguments must have types, and will return a `Error: function argument ZZZ must have a type` if one is not provided. The *record* macro, on the other hand, builds instance variables for the arguments, which, again, require types to be provided at the time of declaration.
#
# A possible partial remediation that would allow one to retrofit the ability to use `send` with methods that aren't already defined with fully typing would be to enable the use of annotations to describe the type signature for the method. This would allow someone to reopen a class, attach type signatures to the methods that need them, and then include `Send` in the class to enable sending to those methods.
#
# ### Methods that take blocks are currently unsupported
#
# This can be supported. The code to do it is still just TODO.
#
# ### Named argument support is flakey
#
# Consider two method definitions:
#
# ```crystal
# def a(b : Int32)
#   puts "b is #{b}"
# end
#
# def a(c : Int32)
#   puts "c is #{c}"
# end
# ```
#
# Only the last one defined, `a(c : Int32)`, will exist in the compiled code. So if you have different methods with the same type signatures, only the last one defined can be addressed using named arguments.
#
# TODO is to see if there is a way to leverage splats and double splats in the send implementation so that all argument handling just works the way that one would expect.
#
# ## Installation
#
# 1. Add the dependency to your `shard.yml`:
#
#     ```yaml
#     dependencies:
#       send:
#         github: your-github-user/send
#     ```
#
# 2. Run `shards install`
#
# ## Usage
#
# ```crystal
# require "send"
#
# class Foo
#   include Send
#   def abc(n : Int32)
#     n * 123
#   end
# end
#
# Send.activate
# ```
#
# When `Send` is included into a class, it registers the class with the Send module, but does no other initialization. To complete initialization, insert a `Send.activate` after all method definitions on the class or struct have been completed. This will setup callsites for all methods that have been defined before that point, which have type definitions on their arguments. By default, this uses *record* callsites for everything. When compiled with `--release`, using *record* callsites is as fast as directly calling the method. If a method uses types that can not be used with an instance variable, but are otherwise legal method types, the *Proc* callsite type can be used instead.
#
# To specify that the entire class should use one callsite type or another, use an annotation on the class.
#
# ```crystal
# @[SendViaProc]
# class Foo
# end
# ```
#
# The `@[SendViaRecord]` annotation is also supported, but since that is the default, one should not need to use it at the class level.
#
# These same annotations can also be used on methods to specify the `send` behavior for a given method.
#
# ```crystal
# @[SendViaProc]
# class Foo
#   def abc(n : Int32)
#     n ** n
#   end
#
#   @[SendViaRecord]
#   def onetwothree(x : Int::Signed | Int::Unsigned, y : Int::Signed | Int::Unsigned)
#     BigInt.new(x) ** BigInt.new(y)
#   end
# end
# ```
#
# The `@[SendSkip]` annotation can be used to indicate that a specific method should be skipped when building callsites for *#send*.
#
# ```crystal
# class Foo
#   def abc(n : Int32)
#     n ** n
#   end
#
#   @[SendSkip]
#   def def(x)
#     yield x
#   end
# end
# ```

module Send
  VERSION = "0.1.4"

  # This excption will be raised if 'send' is invoked for a method that
  # is not mapped.
  class MethodMissing < Exception; end

  private Activated = [false]

  # Constant lookup table for our punctuation conversions.
  SendMethodPunctuationLookups = {
    "LXESXS":        /\s*\<\s*/,
    "EXQUALXS":      /\s*\=\s*/,
    "EXXCLAMATIOXN": /\s*\!\s*/,
    "TXILDXE":       /\s*\~\s*/,
    "GXREATEXR":     /\s*\>\s*/,
    "PXLUXS":        /\s*\+\s*/,
    "MXINUXS":       /\s*\-\s*/,
    "AXSTERISXK":    /\s*\*\s*/,
    "SXLASXH":       /\s*\/\s*/,
    "PXERCENXT":     /\s*\%\s*/,
    "AXMPERSANXD":   /\s*\&\s*/,
    "QXUESTIOXN":    /\s*\?\s*/,
    "LXBRACKEXT":    /\s*\[\s*/,
    "RXBRACKEXT":    /\s*\]\s*/,
  }

  # This macros
  macro build_type_lookup_table(typ)
    {% type = typ.resolve %}
    # This lookup table stores an association of method call signature to method type union, encoded.
    {{ type }}::Xtn::SendTypeLookupByLabel = {
    {% for args in type.methods.map(&.args).uniq %}
      {{args.stringify}}: {{
                                   args.reject do |arg|
                                     arg.restriction.is_a?(Nop)
                                   end.map do |arg|
                                     arg.restriction.resolve.union? ? arg.restriction.resolve.union_types.map do |ut|
                                       ut.id.gsub(/[)(]/, "").gsub(/ \| /, "_")
                                     end.join("_") : arg.restriction.id.gsub(/ \| /, "_").id
                                   end.join("__")
                                 }},
    {% end %}
    }

    # This little table stores the arity of all of the methods, allowing this to be queried at runtime.
    {{ type }}::Xtn::SendArity = Hash(String, Array(Range(Int32, Int32))).new {|h, k| h[k] = [] of Range(Int32, Int32)}
    {% for method in type.methods %}
      {% min = method.args.reject { |m| m.default_value ? true : m.default_value == nil ? true : false }.size %}
      {{ type }}::Xtn::SendArity[{{ method.name.stringify }}] << Range.new({{ min }}, {{ method.args.size }})
    {% end %}

    # This lookup table just captures all of the method names, both as *String* and as *Symbol*,
    # allowing runtime lookup of method names by string.
    {{ type }}::Xtn::SendRespondsTo = {
    {% for method in type.methods.map(&.name).uniq %}
      "{{ method }}": true,
    {% end %}
    }
  end

  macro build_type_lookups(typ)
    {%
      type = typ.resolve
      src = {} of String => Hash(String, String)
      sends = {} of String => Hash(String, Hash(String, String))
      type.methods.reject { |method| method.args.any? { |arg| arg.restriction.is_a?(Nop) } }.map { |method| type.constant(:Xtn).constant(:SendTypeLookupByLabel)[method.args.symbolize] }.uniq.each do |restriction|
        base = restriction.split("__")

        # Figuring out all of the type permutations iteratively took some thinking.
        # The first step is to figre out how many combinations there are.
        permutations = base.map do |elem|
          elem.split("_").size
        end.reduce(1) { |a, x| a *= x }

        combos = [] of Array(String)
        (1..permutations).each { combos << [] of String }
        permutations_step = permutations
        base.each do |b|
          blen = b.split("_").size
          progression = permutations_step / blen
          repeats = permutations / (progression * blen)
          step = 0
          (1..repeats).each do |repeat|
            b.split("_").each do |type_|
              (1..progression).each do |prog|
                combos[step] << type_
                step += 1
              end
            end
          end
          permutations_step = progression
        end

        combos.each do |combo|
          combo_string = combo.join("__").id
          constant_name = "#{type}::Xtn::SendLookup___#{combo.map { |c| c.gsub(/[\(\)]/, "PXAREXN").gsub(/::/, "CXOLOXN") }.join("__").id}" # ameba:disable Style/VerboseBlock
          type.methods.reject { |method| method.args.any? { |arg| arg.restriction.is_a?(Nop) } }.each do |method|
            if !method.annotation(SendSkip) && restriction == type.constant(:Xtn).constant(:SendTypeLookupByLabel)[method.args.symbolize]
              if method.annotation(SendViaProc)
                use_procs = "Y:"
              elsif method.annotation(SendViaRecord)
                use_procs = "N:"
              else
                use_procs = ":"
              end
              idx = -1
              combo_arg_sig = method.args.map { |arg| idx += 1; "#{arg.name} : #{combo[idx].id}" }.join(", ")
              if !src.keys.includes?(constant_name)
                sends[constant_name] = {} of String => String
                src[constant_name] = {} of String => String
              end
              signature = method.args.map { |arg| "#{arg.name} : #{arg.restriction}" }.join(", ")
              sends[constant_name][combo_arg_sig] = {
                "args"      => method.args.map(&.name).join(", "),
                "use_procs" => use_procs,
              }
              method_name = method.name
              ::Send::SendMethodPunctuationLookups.each do |name, punct|
                method_name = method_name.gsub(punct, name.stringify)
              end
              src[constant_name][method.name.stringify] = "#{type}::Xtn::Send_#{method_name}_#{restriction.gsub(/::/, "CXOLOXN").id}"
            end
          end
        end
      end
    %}
    {{ type }}::Xtn::SendRawCombos = {{src.stringify.id}}
    {{ type }}::Xtn::SendParameters = {{sends.stringify.id}}
  end

  macro build_lookup_constants(typ)
    {% type = typ.resolve %}
    {% combo_keys = type.constant(:Xtn).constant(:SendRawCombos).keys %}
    {% for constant_name in combo_keys %}
    {% hsh = type.constant(:Xtn).constant(:SendRawCombos)[constant_name] %}
    {{ constant_name.id }} = {
      {% for method_name, callsite in hsh %}{{method_name}}: {{callsite.id}},
      {% end %}}{% end %}
  end

  # There are two approaches to providing callsites for invoking methods
  # which are currently provided by this library. One approach is to create
  # a bunch of Proc objects which wrap the method calls. The lookup tables
  # can be used to find the correct Proc to call. The other approach is to
  # create a set of `record`s which take the same argument set as the method
  # that it maps to. A `call` method exists on the record, and when invoked,
  # it calls the method using the arguments that were used to create the
  # record.
  #
  # This macro builds the callsites to send methods to. It defaults to using
  # record structs to implement the callsites, but if passed a `true` when the
  # macro is invoked, it will build the callsite using a Proc instead. Callsites
  # built with a record are as fast as direct method invocations, when compiled
  # with `--release`, but they suffer from some type restrictions that the Proc
  # method do not suffer from. Namely, there are some types, such as `Number`,
  # which can be used in a type or type union on a Proc, but which can not be
  # used on an instance variable, which record-type callsites use. However,
  # dynamic dispatch using Proc-type callsites is slower than with record-type
  # callsites.
  macro build_callsites(typ)
    {% type = typ.resolve %}
    {% use_procs = !type.annotations(SendViaProc).empty? %}
    {% for method in type.methods.reject { |method| method.args.any? { |arg| arg.restriction.is_a?(Nop) } } %}
      {%
        method_args = method.args
        method_name = method.name

        safe_method_name = method_name
        ::Send::SendMethodPunctuationLookups.each do |name, punct|
          safe_method_name = safe_method_name.gsub(punct, name.stringify)
        end
      %}
      {% if use_procs == true %}
        {{ type }}::Xtn::Send_{{ safe_method_name }}_{{ type.constant(:Xtn).constant(:SendTypeLookupByLabel)[method.args.symbolize].gsub(/::/, "CXOLOXN").id }} = ->(obj : {{ type.id }}, {{ method_args.map { |arg| "#{arg.name} : #{arg.restriction}" }.join(", ").id }}) do
          obj.{{ method_name }}({{ method_args.map(&.name).join(", ").id }})
        end
      {% else %}
        record {{ type }}::Xtn::Send_{{ safe_method_name }}_{{ type.constant(:Xtn).constant(:SendTypeLookupByLabel)[method.args.symbolize].gsub(/::/, "CXOLOXN").id }}, obj : {{ type.id }}, {{ method_args.map { |arg| "#{arg.name} : #{arg.restriction}" }.join(", ").id }} do
          def call
            obj.{{ method_name }}({{ method_args.map(&.name).join(", ").id }})
          end
        end
      {% end %}
    {% end %}
  end

  # Send needs to find the right method to call, in a world where type unions exist and are
  # common. This may not be the right approach, but it is an approach, and it what I am starting
  # with.
  #
  # The basic problem is that if, say, you have a method that takes a `String | Int32`, and you
  # also have a method that takes only an `Int32`, you will end up with two overloaded `send`
  # methods. If you try to send to the method that takes the union, using a `String`, it will
  # work as expected. However, if you try to send to the method that takes the union, using an
  # Int32, the `send` that takes Int32 will be called, and it needs to be able to find the
  # method that takes the union type.
  macro build_method_sends(typ)
    {%
      type = typ.resolve
      class_use_procs = !type.annotations(SendViaProc).empty?
      send_parameters = type.constant(:Xtn).constant(:SendParameters)
    %}
    {% for constant, hsh in send_parameters %}
    {% for signature, argn in hsh %}
    {%
      args = argn["args"]
      upn = argn["use_procs"]
      if upn == "Y"
        use_procs = true
      elsif upn == "N"
        use_procs = false
      else
        use_procs = class_use_procs
      end
    %}

    {{ type.class? ? "class".id : type.struct? ? "struct".id : "module" }} {{ type }}
    def __send__(method : String, {{ signature.id }})
      begin
      {% if use_procs == true %}
        {{ constant.id }}[method].call(self, {{ args.id }})
      {% else %}
        {{ constant.id }}[method].new(self, {{ args.id }}).call
      {% end %}
      rescue KeyError
        raise MethodMissing.new("Can not send to '#{method}'; check that it exists and all arguments have type specifications.")
      end
    end
    def __send__(method : Symbol, {{ signature.id }})
      __send__(method.to_s, {{ args.id }})
    end
    def send(method : String, {{ signature.id }})
      __send__(method, {{ args.id }})
    end
    def send(method : Symbol, {{ signature.id }})
      __send__(method.to_s, {{ args.id }})
    end

    def __send__?(method : String, {{ signature.id }})
    begin
      {% if use_procs == true %}
        {{ constant.id }}[method].call(self, {{ args.id }})
      {% else %}
        {{ constant.id }}[method].new(self, {{ args.id }}).call
      {% end %}
      rescue KeyError
        return nil
      end
    end
    def send?(method : String, {{ signature.id }})
    __send__(method, {{ args.id }})
    end
    def send?(method : String, {{ signature.id }})
      __send__?(method, {{ args.id }})
    end
    def send?(method : Symbol, {{ signature.id }})
    __send__(method.to_s, {{ args.id }})
    end

    # This incarnation of `#__send__` is a honeypot, to capture method invocations
    # that fail to match anywhere else, which may happen if we try to call a method
    # which does not exist, but we want a runtime error instead of a compile time error.
    def __send__(method : String, *honeypot_args)
      raise MethodMissing.new("Can not send to '#{method}'; check that it exists and all arguments have type specifications.")
    end
    def send(method : String, *honeypot_args)
      __send__(method, *honeypot_args)
    end
    def __send__?(method : String, *honeypot_args)
      raise MethodMissing.new("Can not send to '#{method}'; check that it exists and all arguments have type specifications.")
    end
    def send?(method : String, *honeypot_args)
      __send__?(method, *honeypot_args)
    end

    end
    {% end %}
    {% end %}
  end

  macro included
    {% ClassesToEnable << @type.name %}

    # The standard #responds_to? only takes a symbol, and Crystal doesn't permit
    # String => Symbol, so if one wants to determine if a method exists, where the
    # method name is being built from a String at runtime, there has to be another
    # method to provide this service.
    #
    # `runtime_responds_to?` should, effectively, work just like the builtin method,
    # but it can handle strings as well as symbols.
    def runtime_responds_to?(_method : String | Symbol)
      {{ @type }}::Xtn::SendRespondsTo[_method.to_s.tr(":","")]? || false
    end

    def arity(_method : String | Symbol)
      {{ @type }}::Xtn::SendArity[_method.to_s.tr(":","")]? || [(..)]
    end
  end

  macro activate
    {% if Activated.first %}
      raise "Error. Send.activate() can only be called a single time. Please ensure that activation can not happen multiple times."
    {% else %}
      {% Activated[0] = true %}
      {% for klass in ClassesToEnable.uniq %}
        Send.build_type_lookup_table({{klass.id}})
        Send.build_type_lookups({{klass.id}})
        Send.build_lookup_constants({{klass.id}})
        Send.build_callsites({{klass.id}})
        Send.build_method_sends({{klass.id}})
      {% end %}
    {% end %}
  end
end
