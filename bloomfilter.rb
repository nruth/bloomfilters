# this implementation inefficiently represents each bit as an array of integers

require 'digest/sha1'
require 'digest/md5'
require 'zlib'

class Bloomfilter
  attr_accessor :filter

  def initialize(m=10)
    self.filter = empty_pattern(m)
  end

  # add an object to the filter
  # (with meaningful #to_s, or serialise it youself and pass the string) 
  def insert(obj)
    # add hash to the filter
    bits = filter.zip(hash(obj))
    self.filter = bits.map {|bit1, bit2| bit1 | bit2}
  end

  # does the filter maybe contain obj
  # can give false-positives
  # cannot give false-negatives
  # that is: 
  # if it says it's there, maybe it was inserted
  # if it says it's not there, it was never inserted
  def lookup(obj)
    matches?(hash(obj))
  end
  
  # does the filter contain the pattern's 1 bits?
  def matches?(pattern)
    pattern.zip(filter).all? {|patternbit, filterbit| 
      if patternbit==1 then filterbit==1 else true end 
    }
  end

  # more ruby-like api
  def include?(obj)
    lookup(obj)
  end

  private
  # given some value to store, return its binary hash
  # hash length == filter length
  def hash(obj)
    obj = normalise(obj)
    indices = [Digest::SHA1, Digest::MD5].map do |hasher|
      hasher.digest(obj).unpack("N*").reduce {|accum, n| (accum+n)%filter.length}
    end
    indices << Zlib::crc32(obj)
    pattern = empty_pattern(filter.length)
    indices.each {|index| pattern[index % filter.length ] = 1}
    pattern
  end
  
  def normalise(obj)
    obj.to_s
  end
  
  def empty_pattern(length)
    (1..length).map {0}
  end
end

require 'test/unit'
module BloomfilterTests
  attr_accessor :filter
  
  def test_insertion1
    filter.insert(3)
    assert filter.lookup(3)
  end 
  
  def test_insertion2
    filter.insert(3)
    filter.insert(4)
    filter.insert('foo')
    assert filter.lookup(3)
    assert filter.lookup(4)
    assert filter.lookup('foo')
    
    expected_failures = [2, 5, 'bar']
    refute expected_failures.all? {|x| filter.lookup(x)}
  end 
end

class TestBloomfilter < Test::Unit::TestCase
  include BloomfilterTests
  def setup
    self.filter = Bloomfilter.new
  end
end





# allows element to be deleted even if never added
class NaiveBloomfilterWithDelete < Bloomfilter
  # does the filter contain the pattern's 1 bits?
  def matches?(pattern)
    pattern.zip(filter).all? {|patternbit, filterbit| 
      if (patternbit == 1) then (filterbit >= 1) else true end 
    }
  end
  
  # replace the 0 1 logic with the number of times each 'bit' is inserted
  def delete(obj)
    # remove 1 from each position matching the removed obj's hash
    # set negative counts to 0
    self.filter = filter.zip(hash(obj)).map {|filterbit, hashbit| 
      # remove the requested item
      (filterbit - hashbit)
      # then zero any negative values
    }.map {|x| x > 0 ? x : 0}
  end

  # add an object to the filter
  # (with meaningful #to_s, or serialise it youself and pass the string) 
  def insert(obj)
    # add hash to the filter
    bits = filter.zip(hash(obj))
    self.filter = bits.map {|bit1, bit2| bit1 + bit2}
  end
end


module BasicDeleteFilter
  def test_delete
    filter.insert(3)
    assert filter.lookup(3)
    filter.delete(3)
    refute filter.lookup(3)
  end
end

class TestNaiveBloomfilterWithDelete < Test::Unit::TestCase
  include BloomfilterTests
  include BasicDeleteFilter
  def setup
    self.filter = NaiveBloomfilterWithDelete.new
  end

  def test_allows_deleting_not_inserted_elements
    begin
      filter.delete(4)      
    rescue Exception => e
      flunk("should not fail")
    end
  end
end


class CountingBloomfilterWithDelete < Bloomfilter
  attr_accessor :counts
  def initialize(m=10)
    self.counts = Hash.new
    self.counts.default = 0
    super(m)
  end

  # replace the 0 1 logic with the number of times each 'bit' is inserted
  def delete(obj)
    if self.counts[obj] > 0
      self.counts[obj] -= 1
      self.filter = filter.zip(hash(obj)).map {|filterbit, hashbit| 
        (filterbit - hashbit)
      }
    else
      raise ArgumentError.new("#{obj} not present")
    end
  end

  # add an object to the filter
  # (with meaningful #to_s, or serialise it youself and pass the string) 
  def insert(obj)
    self.counts[obj] += 1
    super
  end
end



class TestCountingBloomfilterWithDelete < Test::Unit::TestCase
  include BloomfilterTests
  include BasicDeleteFilter
  def setup
    self.filter = CountingBloomfilterWithDelete.new
  end
  
  def test_error_if_deleting_something_not_inserted
    assert_raises(ArgumentError) do
      filter.delete(4)
    end
  end
  
  def test_one_delete_per_insertion
    assert_raises(ArgumentError) do
      filter.insert(2)
      filter.delete(2)
      filter.delete(2)
    end
  end
end
