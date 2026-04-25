def cal_points(ops)
  (-> do
    scores = []
    ops.each do |kap_value_1|
      op = kap_value_1
      if op == "C"
        kap_thread_1 = scores.pop
        if kap_thread_1 == nil
          nil
        else
          kap_thread_1.abs
        end
        nil
      elsif op == "D"
        scores.push(2 * scores[-1])
      elsif op == "+"
        scores.push(scores[-1] + scores[-2])
      else
        scores.push(send(:Integer, op))
      end
    end
    scores.sum
  end).call
end
p cal_points(["5", "2", "C", "D", "+"])
p cal_points(["5", "-2", "4", "C", "D", "9", "+", "+"])
