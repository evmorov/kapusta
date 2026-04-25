def kap_qget_path(obj, keys)
  keys.each do |key|
    return if obj.nil?

    obj = obj[key]
  end
  obj
end

private :kap_qget_path

def append(suffix, value)
  (value).to_s + (suffix).to_s
end
def wrap(left, right, value)
  (left).to_s + (value).to_s + (right).to_s
end
def fetch_name(user)
  kap_qget_path(user, [:profile, :name])
end
(-> do
    thread_last = append("!", wrap("[", "]", append(" Lovelace", "Ada")))
  maybe_name = (-> do
      kap_thread_3 = (-> do
        kap_thread_2 = (-> do
          kap_thread_1 = {:profile => {:name => "Ada"}}
        if kap_thread_1 == nil
          nil
        else
          fetch_name(kap_thread_1)
        end
      end).call
      if kap_thread_2 == nil
        nil
      else
        append("!", kap_thread_2)
      end
    end).call
    if kap_thread_3 == nil
      nil
    else
      wrap("<", ">", kap_thread_3)
    end
  end).call
  missing_name = (-> do
      kap_thread_6 = (-> do
        kap_thread_5 = (-> do
          kap_thread_4 = {:profile => nil}
        if kap_thread_4 == nil
          nil
        else
          fetch_name(kap_thread_4)
        end
      end).call
      if kap_thread_5 == nil
        nil
      else
        append("!", kap_thread_5)
      end
    end).call
    if kap_thread_6 == nil
      nil
    else
      wrap("<", ">", kap_thread_6)
    end
  end).call
  thread_first = (-> do
      kap_thread_8 = (-> do
        kap_thread_7 = "kapusta"
      if kap_thread_7 == nil
        nil
      else
        kap_thread_7.upcase
      end
    end).call
    if kap_thread_8 == nil
      nil
    else
      kap_thread_8.reverse
    end
  end).call
  missing_first = (-> do
      kap_thread_10 = (-> do
        kap_thread_9 = nil
      if kap_thread_9 == nil
        nil
      else
        kap_thread_9.upcase
      end
    end).call
    if kap_thread_10 == nil
      nil
    else
      kap_thread_10.reverse
    end
  end).call
  p(thread_last, maybe_name, missing_name, thread_first, missing_first)
end).call
