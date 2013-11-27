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
class TestBloomfilter < Test::Unit::TestCase
  def test_insertion1
    filter = Bloomfilter.new
    filter.insert(3)
    assert filter.lookup(3)
  end 
  
  def test_insertion2
    filter = Bloomfilter.new
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
