def format_record(record)
  name = record[:name]
  role = record[:role]
  tags = record[:tags]
  name.to_s + " / " + role.to_s + " / " + tags.join(", ").to_s
end
record = {:name => "Ada", :role => "engineer", :tags => ["ruby", "lisp"]}
p format_record(record)
