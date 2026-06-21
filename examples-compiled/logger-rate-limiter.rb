require "singleton"

class RateLimiter
  include Singleton

  def initialize
    @last = {}
  end

  def should_print?(timestamp, message)
    last = @last
    if !last.key?(message) || (timestamp >= last[message])
      last[message] = timestamp + 10
      true
    else
      false
    end
  end
end

logger = RateLimiter.instance
p logger.should_print?(1, "foo")
p logger.should_print?(2, "bar")
p logger.should_print?(3, "foo")
p logger.should_print?(8, "bar")
p logger.should_print?(10, "foo")
p logger.should_print?(11, "foo")
p(logger == RateLimiter.instance)
