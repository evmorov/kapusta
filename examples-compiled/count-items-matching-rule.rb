rule_keys = {"type" => :type, "color" => :color, "name" => :name, "rating" => :rating, "category" => :category, "owner" => :owner}

count_matches = nil
count_matches = proc do |items, rule_key, rule_value|
  key = rule_keys[rule_key]
  items.inject(0) do |count, item|
    if item[key] == rule_value
      count + 1
    else
      count
    end
  end
end

items = [{:type => "phone", :color => "blue", :name => "pixel"}, {:type => "computer", :color => "silver", :name => "lenovo"}, {:type => "phone", :color => "gold", :name => "iphone"}]
p count_matches.call(items, "type", "phone")
p count_matches.call(items, "color", "silver")
p count_matches.call(items, "name", "pixel")
