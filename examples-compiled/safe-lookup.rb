def kap_qget_path(obj, keys)
  keys.each do |key|
    return if obj.nil?

    obj = obj[key]
  end
  obj
end

private :kap_qget_path

(-> do
  user = {:profile => {:name => "Ada"}}
  missing = {}
  name = kap_qget_path(user, [:profile, :name])
  missing_name = kap_qget_path(missing, [:profile, :name])
  p(name)
  p(missing_name)
end).call
