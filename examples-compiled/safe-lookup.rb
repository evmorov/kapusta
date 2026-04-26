(-> do
  user = {:profile => {:name => "Ada"}}
  missing = {}
  name = user&.[](:profile)&.[](:name)
  missing_name = missing&.[](:profile)&.[](:name)
  p name
  p missing_name
end).call
