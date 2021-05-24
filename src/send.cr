require "benchmark"

annotation SendViaProc
end

annotation SendViaRecord
end

module Send
  VERSION = "0.1.0"

  macro build_type_label_lookups
    MethodTypeLabel = {
    {% for method in @type.methods %}
      {{method.args.symbolize}} => {{ method.args.map { |arg| arg.restriction.id.gsub(/ \| /, "_").id }.join("__") }},
    {% end %}
    }
  end

  # macro build_type_lookups
  #   {% for restriction in @type.methods.map { |method| MethodTypeLabel[method.args.symbolize] }.uniq %}
  #     SendLookup___{{ restriction.id }} = {
  #       {% for method in @type.methods %}{% if restriction == MethodTypeLabel[method.args.symbolize] %}"{{ method.name }}": Send_{{ method.name }}_{{ restriction.gsub(/::/,"_").id }},
  #       {% end %}{% end %}
  #     }
  #   {% end %}
  # end

  macro build_type_lookups
    SendRawCombos = Hash(String, Hash(String, Array(String))).new {|h,k| h[k] = Hash(String, Array(String)).new}
    {% for restriction in @type.methods.map { |method| MethodTypeLabel[method.args.symbolize] }.uniq %}
      {%
        base = restriction.split("__")
        permutations = restriction.split("__").map do |elem|
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
      %}

      # SendLookup___{{ restriction.id }} = {
      #   {% for method in @type.methods %}{% if restriction == MethodTypeLabel[method.args.symbolize] %}"{{ method.name }}": Send_{{ method.name }}_{{ restriction.gsub(/::/, "_").id }},
      #   {% end %}{% end %}
      # }
      {% for combo in combos %}
      {% combo_string = combo.join("__").id %}
      {% constant_name = "SendLookup___#{combo.join("__").id}" %}
      {% for method in @type.methods %}
      {% if restriction == MethodTypeLabel[method.args.symbolize] %}SendRawCombos[{{constant_name}}][{{method.name.stringify}}] << "Send_{{ method.name }}_{{ restriction.gsub(/::/, "_").id }}"
      {% end %}{% end %}{% end %}{% end %}
  end

  macro p_build_type_lookups
    <<-ECODE
    SendRawCombos = Hash(String, Hash(String, Array(String))).new {|h,k| h[k] = Hash(String, Array(String)).new}
    {% for restriction in @type.methods.map { |method| MethodTypeLabel[method.args.symbolize] }.uniq %}
      {%
        base = restriction.split("__")
        permutations = restriction.split("__").map do |elem|
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
      %}

      # SendLookup___{{ restriction.id }} = {
      #   {% for method in @type.methods %}{% if restriction == MethodTypeLabel[method.args.symbolize] %}"{{ method.name }}": Send_{{ method.name }}_{{ restriction.gsub(/::/, "_").id }},
      #   {% end %}{% end %}
      # }
      {% for combo in combos %}
      {% combo_string = combo.join("__").id %}
      {% constant_name = "SendLookup___#{combo.join("__").id}" %}
      {% for method in @type.methods %}
      {% if restriction == MethodTypeLabel[method.args.symbolize] %}SendRawCombos[{{constant_name}}][{{method.name.stringify}}] << "Send_{{ method.name }}_{{ restriction.gsub(/::/, "_").id }}"
      {% end %}{% end %}{% end %}{% end %}
    ECODE
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
    {% for method in @type.methods %}
      {% method_args = method.args %}
      {% method_name = method.name %}
      {% if use_procs == true %}
        Send_{{ method_name }}_{{ MethodTypeLabel[method.args.symbolize].gsub(/::/, "_").id }} = ->(obj : {{ @type.id }}, {{ method_args.map { |arg| "#{arg.name} : #{arg.restriction}" }.join(", ").id }}) do
          obj.{{ method_name }}({{ method_args.map { |method| method.name }.join(", ").id }})
        end
      {% else %}
        record Send_{{ method_name }}_{{ MethodTypeLabel[method.args.symbolize].gsub(/::/, "_").id }}, obj : {{ @type.id }}, {{ method_args.map { |arg| "#{arg.name} : #{arg.restriction}" }.join(", ").id }} do
          def call
            obj.{{ method_name }}({{ method_args.map { |method| method.name }.join(", ").id }})
          end
        end
      {% end %}
    {% end %}
  end

  macro p_build_callsites
    <<-ECODE
    {% use_procs = !@type.annotations(SendViaProc).empty? %}
    {% for method in @type.methods %}
      {% method_args = method.args %}
      {% method_name = method.name %}
      {% if use_procs == true %}
        Send_{{ method_name }}_{{ MethodTypeLabel[method.args.symbolize].gsub(/::/, "_").id }} = ->(obj : {{ @type.id }}, {{ method_args.map { |arg| "#{arg.name} : #{arg.restriction}" }.join(", ").id }}) do
          obj.{{ method_name }}({{ method_args.map { |method| method.name }.join(", ").id }})
        end
      {% else %}
        record Send_{{ method_name }}_{{ MethodTypeLabel[method.args.symbolize].gsub(/::/, "_").id }}, obj : {{ @type.id }}, {{ method_args.map { |arg| "#{arg.name} : #{arg.restriction}" }.join(", ").id }} do
          def call
            obj.{{ method_name }}({{ method_args.map { |method| method.name }.join(", ").id }})
          end
        end
      {% end %}
    {% end %}
    ECODE
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
  #
  # So....how to do this?
  macro build_method_sends
    {% use_procs = !@type.annotations(SendViaProc).empty? %}
    {% for args in @type.methods.map { |method| method.args }.uniq %}
    def send(method : String, {{ args.map { |arg| "#{arg.name} : #{arg.restriction}" }.join(", ").id }} )
    {% classname = "SendLookup___#{args.map { |arg| arg.restriction.id.gsub(/ \| /, "_").id }.join("__").id}[method]".id %}
    {% arglist = args.map { |arg| arg.name }.join(", ").id %}
    # {% if use_procs == true %}
    #   {{ classname }}.call(self, {{ arglist }})
    # {% else %}
    #   {{ classname }}.new(self, {{ arglist }}).call
    # {% end %}
    end
    {% end %}
  end

  macro p_build_method_sends
    <<-ECODE
    {% use_procs = !@type.annotations(SendViaProc).empty? %}
    {% for args in @type.methods.map { |method| method.args }.uniq %}
    def send(method : String, {{ args.map { |arg| "#{arg.name} : #{arg.restriction}" }.join(", ").id }} )
    {% classname = "SendLookup___#{args.map { |arg| arg.restriction.id.gsub(/ \| /, "_").id }.join("__").id}[method]".id %}
    {% arglist = args.map { |arg| arg.name }.join(", ").id %}
    # {% if use_procs == true %}
    #   {{ classname }}.call(self, {{ arglist }})
    # {% else %}
    #   {{ classname }}.new(self, {{ arglist }}).call
    # {% end %}
    end
    {% end %}
    ECODE
  end

  macro send_init
    build_type_label_lookups
    puts p_build_type_lookups
    # pp "----------"
    # pp SendRawCombos
    puts p_build_callsites
    puts p_build_method_sends
  end

  macro included
    send_init
  end
end
