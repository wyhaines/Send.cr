require "./spec_helper"
require "big"

class TestObj
  def nulltest
    true
  end

  def simple_addition(val : Int32)
    val + 7
  end

  def multiply(x : Int32, y : Int32)
    x * y
  end

  def multiply_plus(val : Int32, val2 : Int32)
    val * val2 + 1
  end

  def exponent(xx : Int32, yy : Int32) : BigInt
    BigInt.new(xx) ** yy
  end

  def complex(x : String | Int32)
    x.to_s
  end

  include Send
end

@[SendViaProc]
class OtherTestObj
  def nulltest
    true
  end

  def num_or_string_to_bigint(val : String | Int32)
    BigInt.new(val.to_s)
  end

  def multiply(x : Int32, y : Int32)
    x * y
  end

  def multimultiply(x : String | Int16 | Int32, y : String | Int16 | Int32)
    x.to_i32 * y.to_i32
  end

  def complex(x : String | Int32)
    x.to_s
  end

  include Send
end

# Benchmark.ips do |ips|
#   ips.report("direct") { f.b(rand(10000), rand(10000)) }
#   ips.report("send") { f.send("b", rand(10000), rand(10000)) }
# end

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

describe Send do
  it "can send messages to methods with simple type signatures" do
    test = TestObj.new

    num = test.simple_addition(7)
    num.should eq test.send("simple_addition", 7)
    test.send("multiply", 7, 9).should eq 63
    (test.send("multiply", 7, 9) + 1).should eq test.send("multiply_plus", 7, 9)

    test.send("exponent", 2, 256).should eq BigInt.new("115792089237316195423570985008687907853269984665640564039457584007913129639936")
  end

  it "can dispatch when the method name is in a variable" do
    test = TestObj.new

    10.times do
      x = rand(20) + 1
      y = rand(20) + 1
      meth = rand ? "multiply" : "exponent"
      expected_answer = meth == "multiply" ? x * y : x ** y
      test.send(meth, x, y).should eq expected_answer
    end
  end

  it "can dispatch to a method that has a complex type signature" do
    test = TestObj.new
    othertest = OtherTestObj.new

    test.send("complex", 7).should eq "7"
    test.send("complex", "7").should eq "7"
    othertest.send("complex", 7).should eq "7"
    othertest.send("complex", "7").should eq "7"
  end

  it "using the Proc method allows dispatch to methods that have types which don't work as instance variables" do
    othertest = OtherTestObj.new

    othertest.send("num_or_string_to_bigint", 7).should eq BigInt.new(7)
    othertest.send("num_or_string_to_bigint", "115792089237316195423570985008687907853269984665640564039457584007913129639936").should eq BigInt.new("115792089237316195423570985008687907853269984665640564039457584007913129639936")
  end

  if ENV.has_key?("BENCHMARK")
    it "runs benchmarks" do
      puts "\n\nBenchmarks..."
      test = TestObj.new
      othertest = OtherTestObj.new

      Benchmark.ips do |ips|
        ips.report("direct method invocation -- nulltest") { test.nulltest }
        ips.report("send via record callsites -- nulltest") { test.send("nulltest") }
        ips.report("send via proc callsites -- nulltest") { othertest.send("nulltest") }
      end

      Benchmark.ips do |ips|
        ips.report("direct method invocation") { test.multiply(rand(10000), rand(10000)) }
        ips.report("send via record callsites") { test.send("multiply", rand(10000), rand(10000)) }
        ips.report("send via proc callsites") { othertest.send("multiply", rand(10000), rand(10000)) }
      end
    end
  end
end
