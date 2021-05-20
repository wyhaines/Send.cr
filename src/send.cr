require "benchmark"

module Send
  VERSION = "0.1.0"

  # This macro will generate a set of lookup tables that can be used to
  # lookup the callsite to use to invoke a given method dynamically.
  # The tables are organized
  macro build_type_lookups
    {% for restriction in @type.methods.map { |method| method.args.map { |arg| arg.restriction.id.tr(" ","").tr("|","_").id }.join("") }.uniq %}
      SendLookup{{ restriction.id }} = {
        {% for method in @type.methods %}{% if restriction == method.args.map { |arg| arg.restriction.id.tr(" ","").tr("|","_").id }.join("") %}"{{ method.name }}": Send_{{ method.name }}{{ restriction.id.tr(" ","").tr("|","_").id }},
        {% end %}{% end %}
      }
    {% end %}
  end

  macro p_build_type_lookups
    <<-ECODE
    {% for restriction in @type.methods.map { |method| method.args.map { |arg| arg.restriction.id.tr(" ","").tr("|","_").id }.join("") }.uniq %}
      SendLookup{{ restriction.id }} = {
        {% for method in @type.methods %}{% if restriction == method.args.map { |arg| arg.restriction.id.tr(" ","").tr("|","_").id }.join("") %}"{{ method.name }}": Send_{{ method.name }}{{ restriction.id.tr(" ","").tr("|","_").id }},
        {% end %}{% end %}
      }
    {% end %}
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
  # This macro creates a set of `record` structs to use to provide a callsite
  # and to encapsulate the arguments for the method.
  macro build_method_records
    {% for method in @type.methods %}
      {% inner_args = method.args %}
      {% inner_method_name = method.name %}
      record Send_{{ inner_method_name }}{{ inner_args.map { |arg| arg.restriction.id.tr(" ","").tr("|","_").id }.join("").id }}, obj : {{ @type.id }}, {{ inner_args.map { |arg| "#{arg.name} : #{arg.restriction}" }.join(", ").id }} do
        def call
          obj.{{ inner_method_name }}({{ inner_args.map { |method| method.name }.join(", ").id }})
        end
      end
    {% end %}
  end

  # This macro will create a set of Procs that wrap the calls to the methods.
  macro build_method_procs
    {% for method in @type.methods %}
      {% inner_args = method.args %}
      {% inner_method_name = method.name %}
      Send_{{ inner_method_name }}{{ inner_args.map { |arg| arg.restriction.id.tr(" ","").tr("|","_").id }.join("").id }} = ->(obj : {{ @type.id }}, {{ inner_args.map { |arg| "#{arg.name} : #{arg.restriction.id.tr(" ","").tr("|","_").id}" }.join(", ").id }}) do
          obj.{{ inner_method_name }}({{ inner_args.map { |method| method.name }.join(", ").id }})
      end
    {% end %}
  end

  macro build_method_sends
    {% for args in @type.methods.map { |method| method.args }.uniq %}
    def send(method : String, {{ args.map { |arg| "#{arg.name} : #{arg.restriction}" }.join(", ").id }})
      SendLookup{{ args.map { |arg| arg.restriction.id.tr(" ","").tr("|","_").id }.join("").id }}[method].new(self, {{ args.map { |arg| arg.name }.join(", ").id }}).call
    end
    {% end %}
  end

  macro build_method_proc_sends
    {% for args in @type.methods.map { |method| method.args }.uniq %}
    def send(method : String, {{ args.map { |arg| "#{arg.name} : #{arg.restriction.id.tr(" ","").tr("|","_").id}" }.join(", ").id }})
      SendLookup{{ args.map { |arg| arg.restriction.id.tr(" ","").tr("|","_").id }.join("").id }}[method].call(self, {{ args.map { |arg| arg.name }.join(", ").id }})
    end
    {% end %}
  end

  macro send_init(use_procs = false)
    build_type_lookups
    {% if use_procs %}
      build_method_procs
      build_method_proc_sends
    {% else %}
      build_method_records
      build_method_sends
    {% end %}
  end

  # macro build_type_lookups
  #   {% for restriction in @type.methods.map do |method|
  #                           method.args.map do |arg|
  #                             arg.restriction
  #                           end.join("")
  #                         end.uniq %}
  #     SendLookup{{ restriction.id }} = {
  #       {% for method in @type.methods %}
  #         {% if restriction == method.args.map { |arg| arg.restriction }.join("") %}
  #           "{{ method.name }}": ->(
  #             obj : {{ @type.id }},
  #           {{ method.args.map do |arg|
  #             "#{arg.name} : #{arg.restriction}"
  #           end.join(", ").id }}
  #         ) do
  #           obj.{{ method.name }}({{ method.args.map { |arg| arg.name }.join(", ").id }})
  #         end,
  #         {% end %}
  #       {% end %}
  #     }
  #   {% end %}
  # end

  # macro build_send_methods
  #   {% for args in @type.methods.map { |method| method.args }.uniq %}
  #   def send(
  #     method : String,
  #     {{ args.map { |arg| "#{arg.name} : #{arg.restriction}" }.join(", ").id }})
  #     SendLookup{{ args.map { |arg| arg.restriction }.join("").id }}[method].call(self, {{ args.map { |arg| arg.name }.join(", ").id }})
  #   end
  #   {% end %}
  # end

  macro send_init
    build_type_lookups
    build_send_methods
  end

  macro included
    send_init
  end
end

require "./send"
require "big"

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

  def d(xx : Int32, yy : Int32) : BigInt
    BigInt.new(xx) ** yy
  end

  include Send
  puts p_build_type_lookups
end


f = Foo.new
puts
puts f.b(7, 9)
puts "------"
10.times {puts f.send(rand < 0.5 ? "b" : "d", rand(20) + 1, rand(20) + 1)}


puts f.send("a", 7)
puts f.send("b", 7, 9)
puts f.send("d", 2, 256)



Benchmark.ips do |ips|
  ips.report("direct") { f.b(rand(10000), rand(10000)) }
  ips.report("send") { f.send("b", rand(10000), rand(10000)) }
end


  # SendLookupInt32 = {
  #   "a": ->(obj : Foo, val : Int32) { obj.a(val) },
  # }

  # SendLookupInt32Int32 = {
  #   "b": ->(obj : Foo, x : Int32, y : Int32) { obj.b(x, y) },
  #   "c": ->(obj : Foo, val : Int32, val2 : Int32) { obj.c(val, val2) },
  # }
  #
  # def send(method, arg1 : Int32)
  #   SendLookupInt32[method].call(self, arg1)
  # end

  # def send(method, arg1 : Int32, arg2 : Int32)
  #   SendLookupInt32Int32[method].call(self, arg1, arg2)
  # end