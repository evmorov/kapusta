def format_record(record)
  (-> do
    name = record[:name]
    role = record[:role]
    tags = record[:tags]
    name.to_s + " / " + role.to_s + " / " + tags.join(", ").to_s
  end).call
end
(-> do
  record = {:name => "Ada", :role => "engineer", :tags => ["ruby", "lisp"]}
  p format_record(record)
end).call
