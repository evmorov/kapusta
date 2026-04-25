class ScopeCounter
  @@total = 0
  def add!(n)
    @@total = @@total + n
    $last_total = @@total
    @@total
  end
  def self.total
    @@total
  end
  a = ScopeCounter.new
  b = ScopeCounter.new
  p a.add!(5)
  p b.add!(4)
  p ScopeCounter.total
  p $last_total
end
ScopeCounter
