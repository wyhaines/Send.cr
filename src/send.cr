require "benchmark"

# Classes or methods with this annotation will use a Proc to wrap method calls.
annotation SendViaProc
end

# Classes or methods with this annotation will use a record to wrap method calls.
annotation SendViaRecord
end

# Methods with this annotation will be skipped when building send call sites.
annotation SendSkip
end

module Send
  VERSION = "0.1.3"

  # This excption will be raised if 'send' is invoked for a method that
  # is not mapped.
  class MethodMissing < Exception; end

  # This macros
  macro build_type_lookup_table
    # Constant lookup table for our punctuation conversions.
    Xtn::SendMethodPunctuationLookups = {
      /\s*\<\s*/ => "LXESXS",
      /\s*\=\s*/ => "EXQUALXS",
      /\s*\!\s*/ => "EXXCLAMATIOXN",
      /\s*\~\s*/ => "TXILDXE",
      /\s*\>\s*/ => "GXREATEXR",
      /\s*\+\s*/ => "PXLUXS",
      /\s*\-\s*/ => "MXINUXS",
      /\s*\*\s*/ => "AXSTERISXK",
      /\s*\/\s*/ => "SXLASXH",
      /\s*\%\s*/ => "PXERCENXT",
      /\s*\&\s*/ => "AXMPERSANXD",
      /\s*\?\s*/ => "QXUESTIOXN",
      /\s*\[\s*/ => "LXBRACKEXT",
      /\s*\]\s*/ => "RXBRACKEXT"
    }

    # This lookup table stores an association of method call signature to method type union, encoded.
    Xtn::SendTypeLookupByLabel = {
    {% for method in @type.methods %}
      {{method.args.symbolize}} => {{
                                     method.args.reject do |arg|
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
    Xtn::SendArity = Hash(String, Array(Range(Int32, Int32))).new {|h, k| h[k] = [] of Range(Int32, Int32)}
    {% for method in @type.methods %}
      {% min = method.args.reject {|m| m.default_value ? true : m.default_value == nil ? true : false}.size %}
      Xtn::SendArity[{{ method.name.stringify }}] << Range.new({{ min }}, {{ method.args.size }})
    {% end %}

    # This lookup table just captures all of the method names, both as *String* and as *Symbol*,
    # allowing runtime lookup of method names by string.
    Xtn::SendRespondsTo = {
    {% for method in @type.methods.map(&.name).uniq %}
      "{{ method }}": true,
    {% end %}
    }
  end

  macro build_type_lookups
    {%
      src = {} of String => Hash(String, String)
      sends = {} of String => Hash(String, Hash(String, String))
      @type.methods.reject { |method| method.args.any? { |arg| arg.restriction.is_a?(Nop) } }.map { |method| Xtn::SendTypeLookupByLabel[method.args.symbolize] }.uniq.each do |restriction|
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
            b.split("_").each do |type|
              (1..progression).each do |prog|
                combos[step] << type
                step += 1
              end
            end
          end
          permutations_step = progression
        end

        combos.each do |combo|
          combo_string = combo.join("__").id
          constant_name = "Xtn::SendLookup___#{combo.map { |c| c.gsub(/[\(\)]/,"PXAREXN").gsub(/::/, "CXOLOXN") }.join("__").id}" # ameba:disable Style/VerboseBlock
          @type.methods.reject { |method| method.args.any? { |arg| arg.restriction.is_a?(Nop) } }.each do |method|
            if restriction == Xtn::SendTypeLookupByLabel[method.args.symbolize]
              if !method.annotations(SendViaProc).empty?
                use_procs = "Y:"
              elsif !method.annotations(SendViaRecord).empty?
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
              Xtn::SendMethodPunctuationLookups.each do |punct, name|
                method_name = method_name.gsub(punct, name)
              end
              src[constant_name][method.name.stringify] = "Xtn::Send_#{method_name}_#{restriction.gsub(/::/, "CXOLOXN").id}"
            end
          end
        end
      end
    %}
    Xtn::SendRawCombos = {{src.stringify.id}}
    Xtn::SendParameters = {{sends.stringify.id}}
  end

  macro build_lookup_constants
    {% combo_keys = Xtn::SendRawCombos.keys %}
    {% for constant_name in combo_keys %}
    {% hsh = Xtn::SendRawCombos[constant_name] %}
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
  macro build_callsites
    {% use_procs = !@type.annotations(SendViaProc).empty? %}
    {% for method in @type.methods.reject { |method| method.args.any? { |arg| arg.restriction.is_a?(Nop) } } %}
      {%
        method_args = method.args
        method_name = method.name

        safe_method_name = method_name
        Xtn::SendMethodPunctuationLookups.each do |punct, name|
          safe_method_name = safe_method_name.gsub(punct, name)
        end
      %}
      {% if use_procs == true %}
        Xtn::Send_{{ safe_method_name }}_{{ Xtn::SendTypeLookupByLabel[method.args.symbolize].gsub(/::/, "CXOLOXN").id }} = ->(obj : {{ @type.id }}, {{ method_args.map { |arg| "#{arg.name} : #{arg.restriction}" }.join(", ").id }}) do
          obj.{{ method_name }}({{ method_args.map(&.name).join(", ").id }})
        end
      {% else %}
        record Xtn::Send_{{ safe_method_name }}_{{ Xtn::SendTypeLookupByLabel[method.args.symbolize].gsub(/::/, "CXOLOXN").id }}, obj : {{ @type.id }}, {{ method_args.map { |arg| "#{arg.name} : #{arg.restriction}" }.join(", ").id }} do
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
  macro build_method_sends
    {% class_use_procs = !@type.annotations(SendViaProc).empty? %}
    {% for constant, hsh in Xtn::SendParameters %}
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
    def send(method : String, {{ signature.id }})
      __send__(method, {{ args.id }})
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
      __send__?(method, {{ args.id }})
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

    {% end %}
    {% end %}
  end

  macro included
    build_type_lookup_table
    build_type_lookups
    build_lookup_constants
    build_callsites
    build_method_sends

    # The standard #responds_to? only takes a symbol, and Crystal doesn't permit
    # String => Symbol, so if one wants to determine if a method exists, where the
    # method name is being built from a String at runtime, there has to be another
    # method to provide this service.
    #
    # `runtime_responds_to?` should, effectively, work just like the builtin method,
    # but it can handle strings as well as symbols.
    def runtime_responds_to?(method : String | Symbol)
      Xtn::SendRespondsTo[method.to_s.tr(":","")]? || false
    end

    def arity(method : String | Symbol)
      Xtn::SendArity[method.to_s.tr(":","")]? || [(..)]
    end
  end
end
