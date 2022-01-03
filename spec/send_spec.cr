require "./spec_helper"
require "big"
require "benchmark"

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
    TestObj::Xtn::Send_exponent_Int32__Int32_false.is_a?(Proc).should be_false
    TestObj::Xtn::Send_exponent_Int32__Int32_false.is_a?(Class).should be_true
    OtherTestObj::Xtn::Send_multimultiply_Int16_Int32_String__Int16_Int32_String.is_a?(Proc).should be_true
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

  it "can call methods with an equal sign or question mark in their name" do
    test = TestObj.new

    test.send("test=", 7)
    test.send("test").should eq 7
    test.send("test?").should be_true
    test.send("[]", 0).should eq '7'
  end

  it "can check the arity of a method at runtime" do
    test = TestObj.new

    test.arity(:test=).size.should eq 2
    test.arity("test=").includes?((1..1)).should be_true
    test.arity(:test=).includes?((0..1)).should be_true
  end

  it "can check if an instance responds to a given method by string name" do
    test = TestObj.new

    test.runtime_responds_to?("test?").should be_true
    test.runtime_responds_to?(:test=).should be_true
  end

  it "methods defined when a class is reopened, and Send is included a second time, work" do
    test = OtherTestObj.new

    test.other_method.should eq 999
  end

  it "methods defined when a class is reopened, and Send is not invoked again, also work" do
    test = OtherTestObj.new

    test.other_other_method.should eq 2345
  end

  it "raises an exception of one attempts to activate the send methods twice" do
    e = nil
    begin
      Send.activate
    rescue e : Exception
    end

    e.should_not be_nil
  end

  it "can skip methods which are marked with the @[SendSkip] annotation" do
    test = TestObj.new

    test.skip_this_one.should be_true
    e = nil
    begin
      test.send(:skip_this_one)
    rescue e : Exception
    end

    e.is_a?(Send::MethodMissing).should be_true
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
