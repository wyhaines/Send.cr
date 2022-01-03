require "spec"
require "../src/send"

class TestObj
  include Send

  @test : String | Int::Signed | Int::Unsigned = ""

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

  def test=(val : String | Int::Signed | Int::Unsigned)
    @test = val
  end

  def test=(val : Float::Primitive = 0.0)
    self.test = val.to_i164
  end

  def test
    @test
  end

  def [](val : Int::Signed | Int::Unsigned)
    @test.to_s[val]
  end

  def <=>(val : String | Int::Signed | Int::Unsigned)
    @test.to_s <=> val.to_s
  end

  def test?
    @test ? true : false
  end

  @[SendSkip]
  def skip_this_one
    true
  end
end

@[SendViaProc]
class OtherTestObj
  include Send

  def nulltest
    true
  end

  def num_or_string_to_bigint(val : String | Int::Signed | Int::Unsigned | Float::Primitive)
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
end

# Test whether we can reopen a class without breaking anything.
class OtherTestObj
  include Send

  def other_method
    999
  end
end

class OtherTestObj
  def other_other_method
    2345
  end
end

# This doesn't work, yet, because we still don't support methods that accept blocks.
# It is closer to working now, though. Generics are better supported.
@[SendViaProc]
class Hash(K, V)
  include Send
end

struct Int32
  include Send
end

Send.activate
