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

  @[SendViaProc]
  def exponent(xx : Int32, yy : Int32) : BigInt
    BigInt.new(xx) ** yy
  end

  def complex(x : String | Int32)
    x.to_s
  end

  def broken(foo)
    foo
  end

  include Send
end

@[SendViaProc]
class OtherTestObj
  def nulltest
    true
  end

  alias Num = Int::Signed | Int::Unsigned | Float::Primitive

  def num_or_string_to_bigint(val : String | Num)
    BigInt.new(val.is_a?(Float) ? val.to_i128 : val.to_s)
  end

  def multiply(x : Int32, y : Int32)
    x * y
  end

  @[SendViaRecord]
  def multimultiply(x : String | Int16 | Int32, y : String | Int16 | Int32)
    x.to_i32 * y.to_i32
  end

  def complex(x : String | Int32)
    x.to_s
  end

  include Send
end

describe Send do
  it "can send messages to methods with simple type signatures" do
    test = TestObj.new

    num = test.simple_addition(7)
    num.should eq test.send("simple_addition", 7)
    test.send("multiply", 7, 9).should eq 63
    (test.send("multiply", 7, 9) + 1).should eq test.send("multiply_plus", 7, 9)

    test.send("exponent", 2, 256).should eq BigInt.new("115792089237316195423570985008687907853269984665640564039457584007913129639936")
  end

  it "raises an exception if the method can't be sent to" do
    test = TestObj.new
    test.broken(7).should eq 7

    e = nil
    begin
      test.send("broken", 7)
    rescue e : Send::MethodMissing
    end

    e.should_not be_nil
    e.class.should eq Send::MethodMissing
  end

  it "will swallow a MethodMissing exception if the ? method is called" do
    test = TestObj.new
    e = nil
    f = nil
    begin
      f = test.send?("broken", 7)
    rescue e : Send::MethodMissing
    end

    e.should be_nil
    f.should be_nil
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

  it "can handle nested, substantial type union combinations" do
    othertest = OtherTestObj.new

    othertest.send("num_or_string_to_bigint", 7).should eq BigInt.new(7)
    othertest.send("num_or_string_to_bigint", 9.83).should eq BigInt.new(9)
    othertest.send("num_or_string_to_bigint", "115792089237316195423570985008687907853269984665640564039457584007913129639936").should eq BigInt.new("115792089237316195423570985008687907853269984665640564039457584007913129639936")
  end

  it "can use annotations to specify whether to use a proc or a record callsite" do
    TestObj::Send_exponent_Int32__Int32.is_a?(Proc).should be_false
    TestObj::Send_exponent_Int32__Int32.is_a?(Class).should be_true
    OtherTestObj::Send_multimultiply_Int16_Int32_String__Int16_Int32_String.is_a?(Proc).should be_true
  end

  # Named parameter support is unavoidably flakey in the current implementation.
  # Send can not overload to methods with the same type signature, but different parameter
  # names. So, while the code will attempt to define a send for every combination of
  # parameter name and type, only the last one of any particular type signature combination
  # will actually exist when the code is compiled.
  #
  # TODO: Is there a way to leverage splats and double-splats to get around this problem?
  it "can call methods using named parameters" do
    test = TestObj.new

    test.send("simple_addition", 7)
    test.send("simple_addition", x: 7)
    test.send(method: "multiply", xx: 7, yy: 9).should eq 63
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
