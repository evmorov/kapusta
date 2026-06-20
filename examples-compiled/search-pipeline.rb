def plan(query)
  "plan:" + query.to_s
end

def run(plan)
  "run:" + plan.to_s
end

{:plan => method(:plan), :run => method(:run)}
