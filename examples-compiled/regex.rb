def parse_date(s)
  re = Kernel.eval("/\\A(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})\\z/")
  (-> do
    kap_case_value_1 = re.match(s)
    case kap_case_value_1
    in nil
      nil
    in m if !m.nil?
      m.named_captures
    else
      nil
    end
  end).call
end
["2026-04-23", "hello", "1999-12-31"].each do |s|
  parsed = parse_date(s)
  p(s.to_s + " -> " + parsed.to_s)
end
