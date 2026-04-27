def append(suffix, value)
  value.to_s + suffix.to_s
end
def wrap(left, right, value)
  left.to_s + value.to_s + right.to_s
end
def fetch_name(user)
  user&.[](:profile)&.[](:name)
end
thread_last = append("!", wrap("[", "]", append(" Lovelace", "Ada")))
maybe_name = (-> do
  thread_3 = (-> do
    thread_2 = (-> do
      thread_1 = {:profile => {:name => "Ada"}}
      if thread_1.nil?
        nil
      else
        fetch_name(thread_1)
      end
    end).call
    if thread_2.nil?
      nil
    else
      append("!", thread_2)
    end
  end).call
  if thread_3.nil?
    nil
  else
    wrap("<", ">", thread_3)
  end
end).call
missing_name = (-> do
  thread_6 = (-> do
    thread_5 = (-> do
      thread_4 = {:profile => nil}
      if thread_4.nil?
        nil
      else
        fetch_name(thread_4)
      end
    end).call
    if thread_5.nil?
      nil
    else
      append("!", thread_5)
    end
  end).call
  if thread_6.nil?
    nil
  else
    wrap("<", ">", thread_6)
  end
end).call
thread_first = (-> do
  thread_8 = (-> do
    thread_7 = "kapusta"
    if thread_7.nil?
      nil
    else
      thread_7.upcase
    end
  end).call
  if thread_8.nil?
    nil
  else
    thread_8.reverse
  end
end).call
missing_first = (-> do
  thread_10 = (-> do
    thread_9 = nil
    if thread_9.nil?
      nil
    else
      thread_9.upcase
    end
  end).call
  if thread_10.nil?
    nil
  else
    thread_10.reverse
  end
end).call
p(thread_last, maybe_name, missing_name, thread_first, missing_first)
