def parse_int(s)
  Kernel.public_send(:Integer, s)
end
(-> do
  ok, value = begin
    [true, parse_int("12")]
  rescue StandardError => e
    [false, e]
  end
  bad_ok, error = begin
    [true, parse_int("oops")]
  rescue StandardError => e
    [false, e]
  end
  handled_ok, handled = begin
    [true, parse_int("oops")]
  rescue StandardError => e
    [false, (proc do |e|
      e.message
    end).call(e)]
  end
  p ok
  p value
  p bad_ok
  p error.class
  p handled_ok
  p handled
end).call
