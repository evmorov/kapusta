class RecentCounter
  def initialize
    @pings = []
  end
  def ping(t)
    pings = @pings
    pings.push(t)
    while pings[0] < (t - 3000)
      pings.shift
    end
    pings.length
  end
  def self.warm(history)
    c = RecentCounter.new
    history.each do |t|
      c.ping(t)
    end
    c
  end
end
c = RecentCounter.warm([100, 200, 300])
p c.ping(3001)
p c.ping(3002)
